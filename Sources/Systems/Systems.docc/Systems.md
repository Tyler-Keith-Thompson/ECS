# ``Systems``

Declare the rules of a simulation as systems, and run them on a world in a schedule.

## Overview

A world holds data: entities and their components, and resources. A *system* holds a rule: a
step that reads part of the world and changes part of it, such as "every entity with a velocity
moves" or "gravity pulls on everything that isn't frozen." A *schedule* lists the systems of one
frame or step and runs them on a world, each once per run.

The examples throughout this module use these components, resources and event:

```swift
struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }
struct Health: Component { var current: Int }
struct Frozen: Component {}

struct Score: Resource { var points: Int }
struct TimeStep: Resource { var seconds: Double }
struct Paused: Resource {}

struct Damage: Event { var target: Entity, amount: Int }
```

### Declare a System

The simplest way to write a system is to mark a type with the `@System` macro and give it a
`run` method. The method's parameters say what the system works on, and their types say how:
an ``Update`` writes components, a ``/WorldModule/Query`` reads them, and a ``ResourceReader``
reads a resource. The following two systems pull everything that isn't frozen downward, then move
it by its velocity:

```swift
@System
struct Gravity {
    func run(_ falling: Update<Velocity>.Where<Without<Frozen>>) {
        falling { velocity, _ in velocity.dy -= 10 }
    }
}

@System
struct Movement {
    func run(_ movers: Update<Position>.Over<Velocity>.Where<Without<Frozen>>) {
        movers { position, row in
            position.x += row.components.dx
            position.y += row.components.dy
        }
    }
}
```

Because the parameters' types state what each system reads and writes, the macro writes the
system's ``System/access`` for you: `Gravity` writes `Velocity`; `Movement` writes `Position` and
reads `Velocity`. A schedule uses the access to decide which systems can run at the same time.

You can also conform a type to ``System`` by hand and write its ``System/run(in:)`` method, which
receives the whole world. See ``System`` for when to do that.

### Run Systems in a Schedule

A ``Schedule`` is built from a list of systems, written in a result builder. Running it runs each
system once. The following example drops a ball for one frame:

```swift
var world = World()
let ball = world.spawn(Position(x: 0, y: 100), Velocity(dx: 1, dy: 0))

let frame = Schedule {
    Gravity()
    Movement().after(Gravity.self)
}
frame.run(on: &world)

print(world[Position.self, of: ball])
// Prints "Position(x: 1.0, y: 90.0)"
```

Systems run in the order you write them, unless an ordering constraint says otherwise.
`after(_:)` and `before(_:)` require one system to run after or before another; ``SystemSet``
names a group of systems so constraints can refer to all of them at once; and `runIf(_:)` skips
a system when a condition doesn't hold.

Systems whose accesses don't conflict, because neither writes what the other reads or writes,
run at the same time, and the world ends as though they had run one after another (commands
apply when each wave finishes). Systems that
conflict run in order. When two conflicting systems aren't ordered by any constraint, their order
rests only on how they happen to be written; ``Schedule/ambiguities()`` finds those pairs so a
test can keep a schedule free of them.

## Topics

### Essentials

- <doc:DeclaringSystems>
- ``System()``
- ``System``

### System Parameters

- ``SystemParameter``
- ``Update``
- ``ResourceReader``
- ``ResourceWriter``
- ``EventReader``
- ``EventWriter``
- ``RemovedComponents``

### Building and Running Schedules

- ``Schedule``
- ``ScheduleBuilder``
- ``ScheduledSystem``
- ``SystemSet``
- ``CyclicOrdering``
- ``Ambiguity``

### Main-Actor Systems

- ``MainActorSystem``

### Built-In Systems

- ``UpdateEvents``
- ``ForwardEvents``
- ``ForwardChanges``

### Profiling

- ``SystemProfile``
- ``SystemTiming``
