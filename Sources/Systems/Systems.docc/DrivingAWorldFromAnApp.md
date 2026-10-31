# Driving a World from an App

Hold a world in your app or game engine, feed it each frame's input, and let the objects outside
it read results and take part in a step.

## Overview

A world is a value, and a schedule changes it through an `inout` parameter. The code that drives
it, such as a game engine's frame callback or an app's model object, owns the world, runs a
schedule on it, and reads the results. This article shows how to pass input in, how to hold the
world, and how objects outside the world can take part in a step while a schedule runs.

### Pass Each Run's Input Through a Resource

A system's ``System/run(in:)`` method receives only the world, so input that changes from run to
run, such as the time since the last frame or the buttons held down, goes into a resource before
each run. Systems read it with a ``ResourceReader`` like any other resource:

```swift
@System
struct Integrate {
    func run(_ movers: Update<Position>.Over<Velocity>, _ step: ResourceReader<TimeStep>) {
        movers { position, row in
            position.x += row.components.dx * step.value.seconds
            position.y += row.components.dy * step.value.seconds
        }
    }
}

var world = World()
let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 2, dy: 0))
let frame = Schedule { Integrate() }

for delta in [0.5, 0.25] {
    world.resources.insert(TimeStep(seconds: delta))
    frame.run(on: &world)
}
print(world[Position.self, of: ball].x)
// Prints "1.5"
```

Inserting a resource replaces the one of the same type, so the schedule stays the same from frame
to frame; there is no need to rebuild it, or to store the input in a system. A system's declared
access lists the resource like any other, so a schedule still knows which systems can run at the
same time.

### Hold the World in a Final Class

An app's model object or an engine's node usually owns the world. Store it in a stored `var`
property of a `final` class, and run schedules on that property:

```swift
@MainActor
final class Game {
    var world = World()
    let frame = Schedule { Integrate() }

    func advance(by seconds: Double) {
        world.resources.insert(TimeStep(seconds: seconds))
        frame.run(on: &world)
    }
}

let game = Game()
let rocket = game.world.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: 4))
game.advance(by: 0.5)
print(game.world[Position.self, of: rocket].y)
// Prints "2.0"
```

Reading through a stored property, as `game.world[Position.self, of: rocket]` does, reads the
world in place. A getter that returns a world, such as a computed property or a protocol
requirement the compiler can't see through, returns a copy instead. A copy shares the world's
storage rather than duplicating it, but it costs more than reading in place on every access; in a
loop that reads many values, read through the stored property or pass the world down as shown
next.

### Let Outside Objects Take Part in a Step

While a schedule runs, it has exclusive access to the world it was given. An object that reaches
back to the property holding the world during the run, such as a view that reads `game.world`
from inside a system, overlaps that access, and Swift stops the program with an exclusivity
violation.

Instead, pass the world to the object. Give it a method that takes the world as an `inout`
parameter, and call that method from a ``MainActorSystem`` that holds the object:

```swift
@MainActor
final class Sprite {
    let entity: Entity
    var x = 0.0

    init(entity: Entity) { self.entity = entity }

    func step(in world: inout World) {
        x = world[Position.self, of: entity].x
    }
}

struct SyncSprites: MainActorSystem {
    let sprites: [Sprite]
    var access: Access? { .reads(Position.self) }

    @MainActor func run(in world: inout World) {
        for sprite in sprites { sprite.step(in: &world) }
    }
}

var world = World()
let ship = world.spawn(Position(x: 0, y: 0), Velocity(dx: 3, dy: 0))
let sprite = Sprite(entity: ship)
world.resources.insert(TimeStep(seconds: 1))

let frame = Schedule {
    Integrate()
    SyncSprites(sprites: [sprite]).after(Integrate.self)
}
frame.run(on: &world)
print(sprite.x)
// Prints "3.0"
```

The object reads and writes the world it is handed, and the schedule orders its work with the
other systems like any other system's. A main-actor system runs on the main actor, so it can call
into views and other objects isolated to it.

### Perform Effects Before a Step Continues

Events suit effects the outside handles later: a system sends them, and the outside reads them
after the schedule runs. Some effects have to happen before the step goes on, such as a message
the view must show before the next system changes what it describes. A main-actor system calls
the object directly, and the call returns before the next system in the schedule starts:

```swift
@MainActor
final class MessageLog {
    var lines: [String] = []
}

struct AnnounceDefeats: MainActorSystem {
    let log: MessageLog
    var access: Access? { .reads(Health.self) }

    @MainActor func run(in world: inout World) {
        for (_, health) in world.query(Health.self) where health.current <= 0 {
            log.lines.append("A fighter falls")
        }
    }
}

var world = World()
let knight = world.spawn(Health(current: 10))
world.send(Damage(target: knight, amount: 12))

let log = MessageLog()
let turn = Schedule {
    ApplyDamage()
    AnnounceDefeats(log: log).after(ApplyDamage.self)
    RemoveDefeated().after(AnnounceDefeats.self)
}
turn.run(on: &world)
print(log.lines)
// Prints "["A fighter falls"]"
print(world.contains(knight))
// Prints "false"
```

When the outside needs more than one call to respond, such as an animation that must finish
first, end the step there: split the work into two schedules, run the first, and run the second
when the outside reports that it is done.

### Keep Main-Actor State in a Resource

Resources and components are `Sendable`, because a schedule runs systems on other threads and a
copy of a world can go anywhere. To keep a value that isn't `Sendable` with the world, such as a
script interpreter or an engine object, put it in a class isolated to the main actor, and store
that class in a resource. A class isolated to a global actor is `Sendable` whatever it holds, and
only main-actor code, such as a ``MainActorSystem``, can reach its contents:

```swift
final class Script {
    var line = 0
    func advance() { line += 1 }
}

@MainActor
final class StoryState {
    let script = Script()
}

struct Story: Resource {
    let state: StoryState
}

struct AdvanceStory: MainActorSystem {
    var access: Access? { .reads(resources: Story.self) }

    @MainActor func run(in world: inout World) {
        world.resources[Story.self].state.script.advance()
    }
}

var world = World()
world.resources.insert(Story(state: StoryState()))
let turn = Schedule { AdvanceStory() }
turn.run(on: &world)
turn.run(on: &world)
print(world.resources[Story.self].state.script.line)
// Prints "2"
```

The resource holds a reference, so every copy of the world shares the one `StoryState`. Changing
it changes it for every copy, and saving or restoring a world doesn't save or restore it.
