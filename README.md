# ECS

An entity component system for Swift: entities are handles, components are plain values stored
per type in sparse sets, and systems are rules run over them in a declared order. It fits games,
simulations and anything else that updates many similar things each step. The world is a value,
so it can be copied for a snapshot, an undo step or a rollback, and the copy shares storage until
one side writes.

[Documentation](https://tyler-keith-thompson.github.io/ECS/documentation/)

## Installation

ECS requires Swift 6.3 and supports macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2
or later.

```swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/ECS", from: "0.0.1"),
],
```

Then add a product to your target, either the umbrella or individual modules:

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "ECS", package: "ECS"),
    // or, for example:
    // .product(name: "WorldModule", package: "ECS"),
]),
```

## Usage

Every example here is a test in `Tests/ECSTests`, so it cannot drift from the code.

```swift
import ECS

struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }
struct Health: Component { var current: Int }
struct Frozen: Component {}
struct Clock: Resource { var ticks = 0 }

@System
struct Movement {
    func run(_ movers: Update<Position>.Over<Velocity>.Where<Without<Frozen>>) {
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

@System
struct Tick {
    func run(clock: ResourceWriter<Clock>) {
        clock.value.ticks += 1
    }
}

var world = World()
world.resources.insert(Clock())

let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2), Health(current: 3))
let wall = world.spawn(Position(x: 5, y: 0), Velocity(dx: 9, dy: 9), Frozen())
let ghost = world.spawn(Health(current: 0))

let tick = Schedule {
    Reaper().after(Movement.self)
    Movement()
    Tick()
}
tick.run(on: &world)

print(tick.names)                     // ["Movement", "Reaper", "Tick"]
print(world[Position.self, of: ball]) // Position(x: 1.0, y: 2.0)
print(world[Position.self, of: wall]) // Position(x: 5.0, y: 0.0)
print(world.contains(ghost))          // false
print(world.resources[Clock.self])    // Clock(ticks: 1)

for (entity, position, velocity) in world.query(Position.self, Velocity.self).without(Frozen.self) {
    print(entity, position, velocity)
}
```

### The pieces

- **`Entity`**: a slot and a generation. A despawned entity's handle goes stale instead of naming
  whatever reuses its slot.
- **`World`**: `spawn`, `despawn`, `insert`, `remove`, and `world[Type.self, of: entity]` to read
  or change one component in place. Plain spellings trap on a stale entity; `checked` spellings
  throw.
- **`query`**: a lazy view of the entities holding every listed type, narrowed with `with` and
  `without`. Each row is a tuple, `(entity, component, …)`. A view is a snapshot; writing to the
  world while iterating is safe.
- **`Query`**: a query as a value, kept and run against any world. `AnyOf<Wind, Current>`
  matches entities holding at least one of its types and yields a tuple of optionals, and
  `.anyOf(…)` filters pass entities meeting at least one condition:

  ```swift
  let drifting = Query(AnyOf<Wind, Current>.self).without(Anchored.self)
  world.update(Position.self, over: drifting) { position, row in
      let (wind, current) = row.components
      position.x += (wind?.speed ?? 0) + (current?.speed ?? 0)
  }
  for (entity, position, (wind, current)) in world.query(Query(Position.self, AnyOf<Wind, Current>.self)) {
      print(entity, position, wind?.speed ?? 0, current?.speed ?? 0)
  }
  ```
- **`update`**: changes one or two component types in place across every matching entity,
  reading any others, or one to three types over a `Query`. This is the fast path for systems. `parallelUpdate` spreads one across cores, with
  the same result. `world.group(Position.self, Velocity.self)` keeps two or more types
  packed in the same order, so queries and updates over exactly those types make no lookups.
- **Change detection**: every component remembers when it was added and last changed.
  `query(…).changed(Position.self)` inside a system lists what changed since that system last
  ran; `.added(…)` lists what is new. Outside a schedule, pass a tick: `since: checkpoint`.
- **Bundles**: a `Bundle` lists components that go together in a `body`, with `if` and
  `switch`; spawn, insert and remove it as one. Every component is a bundle of itself.
- **Required components**: a component lists others it needs in `static var required`, and
  spawning or inserting it adds each one the entity lacks, transitively; components given
  explicitly win.
- **Hooks**: `world.onAdd(Name.self) { world, entity in … }`, `onInsert` and `onRemove` run
  after the operation that fired them, for keeping indexes without polling.
- **Removal detection**: `world.removed(Health.self, by: Healthbars.self)` lists the entities
  that lost a `Health` since that reader last asked, by removal or despawn; a system takes
  `RemovedComponents<Health>`.
- **Hierarchy**: `try world.addChild(turret, to: ship)`; `parent(of:)`, `children(of:)`,
  `ancestors(of:)` and `descendants(of:)` walk it, and despawning an entity despawns its
  descendants.
- **Events**: `world.send(Collision(…))` in one system, `world.readEvents(Collision.self,
  by: Damage.self)` in another. Each reader reads each event once; an `UpdateEvents` system at the
  start of a frame drops events older than the previous frame.
- **Snapshots**: `world.snapshot(Position.self, Velocity.self)` is `Codable`;
  `World(restoring:)` rebuilds the world with every entity handle unchanged. Snapshots of
  `Equatable` components compare with `==`, which is how to compare two worlds.
- **`Commands`**: spawns, despawns and insertions recorded during an update and applied after it.
  `commands.spawn(…)` returns a handle later commands in the buffer can name.
- **`Resources`**: values the world holds once, such as a clock or the frame's input.
- **`@System`**: a system declared by its `run` method's parameters, whose types state what it
  reads and writes: `Query<…>` and `Query<…>.Where<…>` read components,
  `Update<A>.And<B>.Over<…>.Where<…>` writes them, `ResourceReader`, `ResourceWriter`,
  `EventReader`, `EventWriter` and `RemovedComponents` reach resources, events and removals,
  and `inout Commands` queues structural changes that apply after the system's wave. The filter
  types `With`, `Without`, `Added`, `Changed` and `AnyOf` mirror the filter values. Parameters
  that conflict are a compile-time error. A `run(in world: inout World)` makes a system that may
  change anything.
- **`Schedule`**: systems in the order written, adjusted by `after` and `before` constraints,
  and skipped when a `runIf { world in … }` condition does not hold. `run(on:)` runs systems
  that neither conflict nor are ordered at the same time, in waves, with the result running them
  in order gives; `runSerially(on:)` runs the same waves one system at a time. A system's access
  comes from its parameters, or from `access` declared by hand; a system without one runs alone.
  `ambiguities()` lists conflicting systems no constraint orders, whose order rests on how they
  were written.
- **`Simulation`**: a world and schedules by label, stepped with `update(elapsed:)`:
  `.startup` before the first frame, then each frame `.fixedUpdate` once per fixed timestep
  elapsed and `.update`. A `States` type (`enum GameState: States { … }`) runs `.onEnter`,
  `.onExit` and `.onTransition` schedules when a system sets `NextState`, and `inState(…)` is a
  run condition.

Queries and updates of up to three types have overloads the compiler fully specializes; more types
go through a parameter pack.

## Modules

| Module | Holds |
|---|---|
| `WorldModule` | `World`, `Entity`, `Component`, `Resource`, queries, updates and `Commands` |
| `Systems` | `System`, `@System` and its parameters, and `Schedule`, ordered with [Grafluent](https://github.com/Tyler-Keith-Thompson/Grafluent) |
| `SimulationModule` | `Simulation`: a world and its schedules by label, a fixed timestep and states |

## Development

Bazel is the development build; SwiftPM is the published package. Both are generated from
`scripts/modules.py`.

| Command | Does |
|---|---|
| `just test` | Build and run every test |
| `just verify` | The tests under Bazel and under SwiftPM |
| `just modules` | Regenerate `Package.swift` and every `BUILD.bazel` |
| `just docs` | The DocC site into `.build/docs` |
| `just generate` | An Xcode project from the Bazel graph |

`AGENTS.md` describes the layout, the workflow and the house rules in full.

## License

Apache 2.0. See `LICENSE`.
