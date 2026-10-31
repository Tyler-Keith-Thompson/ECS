# Getting Started with ECS

Define components, spawn entities, and move them with systems that run in a schedule and a
simulation.

## Overview

In an entity component system, the things your program tracks are *entities*: plain handles that
own nothing themselves. The data lives in *components*, small value types attached to entities,
such as a position or a health bar. The behavior lives in *systems*, functions that run over
every entity holding a particular set of components. A *world* holds the entities and their
components, and a *schedule* runs systems on it.

This article builds a tiny game step by step: balls that move, and that disappear when their
health runs out.

### Define Components

A component is a value type that conforms to ``/WorldModule/Component``. It needs no other
requirements; a struct with stored properties is enough. A component can also be empty, to mark
the entities that have it.

The following components describe where an entity is, how fast it moves, and how much health it
has:

```swift
struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }
struct Health: Component { var current: Int }
```

### Spawn Entities

A ``/WorldModule/World`` holds entities and their components. Create an empty world, then call
`spawn(_:)` with the components a new entity starts with. Spawning returns an
``/WorldModule/Entity``, the handle you use to read and change that entity later:

```swift
var world = World()
let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
let rock = world.spawn(Position(x: 5, y: 5))
print(world.count)
// Prints "2"

world[Position.self, of: ball].x = 10
print(world[Position.self, of: ball])
// Prints "Position(x: 10.0, y: 0.0)"

world.insert(Health(current: 3), into: rock)
print(world.contains(Health.self, in: rock))
// Prints "true"
```

The subscript reads one component of one entity, and changes it in place when you assign through
it. Use `insert(_:into:)` to add a component to an entity, `remove(_:from:)` to take one away,
and `despawn(_:)` to remove the entity and all of its components.

A world is a value: assigning it to another variable makes an independent copy, and the two
share their storage until one of them changes.

- Important: Like an array subscript, the subscript traps if the entity doesn't hold the
  component, or has been despawned. Each such operation has a `checked` spelling, such as
  `world[checked: Position.self, of: ball]`, that throws an error instead.

### Query and Update Many Entities

A query visits every entity holding a set of component types. Call `query(_:)` with the types,
and iterate over the result; each row holds the entity followed by its components. Narrow a
query with `with(_:)` and `without(_:)`:

```swift
var world = World()
world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
world.spawn(Position(x: 5, y: 5))

for (_, position) in world.query(Position.self).without(Velocity.self) {
    print(position)  // Prints "Position(x: 5.0, y: 5.0)"
}
```

To change components across many entities, use `update(_:reading:body:)`. It visits every
entity holding the written type and the read types, and passes the written component `inout`
along with a row of the others. This is the fastest way to change many entities:

```swift
var world = World()
let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
let rock = world.spawn(Position(x: 5, y: 5))

world.update(Position.self, reading: Velocity.self) { position, row in
    position.x += row.components.dx
    position.y += row.components.dy
}
print(world[Position.self, of: ball])
// Prints "Position(x: 1.0, y: 2.0)"
print(world[Position.self, of: rock])
// Prints "Position(x: 5.0, y: 5.0)"
```

The rock has no velocity, so the update skips it.

### Write Systems

A system is a rule your program applies over and over, such as moving everything that has a
velocity. Declare one with the ``/Systems/System()`` macro on a type with a `run` method. The
types of the method's parameters say what the system reads and writes:
``/Systems/Update`` writes components, ``/WorldModule/Query`` reads them, and an `inout`
``/WorldModule/Commands`` records spawns and despawns to apply after the system runs.

The following systems move each entity by its velocity, and despawn each entity whose health has
run out:

```swift
@System
struct Movement {
    func run(_ movers: Update<Position>.Over<Velocity>) {
        movers { position, row in
            position.x += row.components.dx
            position.y += row.components.dy
        }
    }
}

@System
struct Reaper {
    func run(_ living: Query<Health>, commands: inout Commands) {
        for (entity, health) in living where health.current <= 0 {
            commands.despawn(entity)
        }
    }
}
```

Because a system states what it touches, a schedule knows which systems can run at the same
time. Two parameters whose types conflict, such as two updates of the same component, are a
compile-time error.

### Run a Schedule

A ``/Systems/Schedule`` runs systems in the order you write them. Call
``/Systems/Schedule/run(on:)`` to run every system once on a world:

```swift
var world = World()
let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2), Health(current: 3))
let ghost = world.spawn(Position(x: 0, y: 0), Health(current: 0))

let frame = Schedule {
    Movement()
    Reaper()
}
frame.run(on: &world)

print(world[Position.self, of: ball])
// Prints "Position(x: 1.0, y: 2.0)"
print(world.contains(ghost))
// Prints "false"
```

Systems that don't conflict, like these two, run at the same time; the result is always the
same as running them one after another in the order written. To order systems differently, add
a constraint such as `Reaper().after(Movement.self)`, and to skip a system unless a condition
holds, add `runIf(_:)`.

### Run a Simulation

A game or simulation runs its systems every frame. A ``/SimulationModule/Simulation`` owns a world
and schedules named by label, and you call ``/SimulationModule/Simulation/update(elapsed:)`` once a
frame with the time that passed. Systems added to the
``/SimulationModule/ScheduleLabel/fixedUpdate`` label run once for every fixed timestep of that
time, so they advance at the same rate however long each frame takes:

```swift
var world = World()
let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2), Health(current: 3))

var simulation = Simulation(world, fixedTimestep: .milliseconds(10))
simulation.add(to: .fixedUpdate) { Movement() }
simulation.add(to: .update) { Reaper() }

simulation.update(elapsed: .milliseconds(30))
print(simulation.world[Position.self, of: ball])
// Prints "Position(x: 3.0, y: 6.0)"
```

The 30-millisecond frame covers three timesteps, so `Movement` runs three times. Because it
moves each entity by its velocity once a run, the velocity here is a distance per timestep. A
system that needs the length of a step reads the ``/SimulationModule/FixedTime`` resource, and one
that needs the length of a frame reads ``/SimulationModule/Time``.

### Next Steps

- Learn about the world in depth, including bundles, relations, hierarchies, events and change
  detection, in ``/WorldModule``.
- Learn about system parameters, ordering and system sets in ``/Systems``.
- Learn about states and the order of a frame in ``/SimulationModule``.
