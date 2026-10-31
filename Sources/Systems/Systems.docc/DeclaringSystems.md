# Declaring Systems

Write the rules of a simulation as systems, and let their parameters state what they read and
write.

## Overview

A system is a type with a `run` method that a schedule calls once per run. The ``System()``
macro turns a structure into a system from the parameters of its `run` method. Each parameter's
type says what part of the world the system works on and whether it reads or writes it, so the
system's ``System/access`` is always exact, and a schedule can run systems that don't conflict at
the same time.

### Read and Write Components

Take a ``/WorldModule/Query`` to read components, and iterate it as you would a world's query
results. Take an ``Update`` to change them in place. An
update can also read other components with `Over`, and narrow the entities it visits with
`Where`:

```swift
@System
struct Climb {
    func run(_ climbers: Update<Position>.Over<Velocity>.Where<Without<Frozen>>) {
        climbers { position, row in
            position.y += abs(row.components.dy)
        }
    }
}

var world = World()
let climber = world.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: -3))
let statue = world.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: -3), Frozen())
Schedule { Climb() }.run(on: &world)

print(world[Position.self, of: climber].y)
// Prints "3.0"
print(world[Position.self, of: statue].y)
// Prints "0.0"
```

`Climb` writes `Position` and reads `Velocity` and `Frozen`. It conflicts with any system that
writes `Velocity` or `Frozen`, or reads or writes `Position`, and runs at the same time as any
other.

### Read and Write Resources and Events

A ``ResourceReader`` reads a resource and a ``ResourceWriter`` changes one. An ``EventWriter``
sends events, and an ``EventReader`` reads the events sent since the system last read them. The
following schedule sends a `Damage` event for each entity below the ground, then applies the
damage to its target's health:

```swift
var world = World()
let knight = world.spawn(Position(x: 0, y: -1), Health(current: 30))

let frame = Schedule {
    UpdateEvents()
    Combat()
    ApplyDamage().after(Combat.self)
}
frame.run(on: &world)
print(world[Health.self, of: knight].current)
// Prints "20"
```

``EventWriter`` declares `Combat`, and ``EventReader`` declares `ApplyDamage`.

### Spawn and Despawn Entities

A system that runs alongside others can't spawn or despawn entities directly, because that
changes every component type at once. Take an `inout` ``/WorldModule/Commands`` instead, and queue
the changes. Commands apply at the end of the wave the system runs in, so systems ordered after
it see them:

```swift
@System
struct RemoveDefeated {
    func run(_ fighters: Query<Health>, _ commands: inout Commands) {
        for (entity, health) in fighters where health.current <= 0 {
            commands.despawn(entity)
        }
    }
}

var world = World()
let knight = world.spawn(Health(current: 0))
world.spawn(Health(current: 12))
Schedule { RemoveDefeated() }.run(on: &world)

print(world.contains(knight))
// Prints "false"
print(world.count)
// Prints "1"
```

A commands parameter conflicts with nothing, so it doesn't stop a system from running at the
same time as others.

### Take the Whole World

A `run` method that takes `inout World` makes a system that can change anything. Its access is
`nil`, so a schedule runs it alone, after the systems written before it and before those written
after it. Use one for work that touches many types at once, such as loading a level.

To write a system by hand instead of with the macro, conform a type to ``System``, implement
``System/run(in:)``, and declare an ``System/access`` listing every type the system reads and
writes.

### Run on the Main Actor

Mark a system type, or its `run` method, `@MainActor` to make a ``MainActorSystem``, which a
schedule runs on the main actor after the other systems of its wave. Use one to carry results
from the world to a user interface.

## Topics

### Declaring Systems

- ``System()``
- ``System``
- ``MainActorSystem``

### System Parameters

- ``Update``
- ``ResourceReader``
- ``ResourceWriter``
- ``EventReader``
- ``EventWriter``
- ``RemovedComponents``
