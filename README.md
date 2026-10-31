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

struct Movement: System {
    func run(in world: inout World) {
        world.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, row in
            position.x += row.components.dx
            position.y += row.components.dy
        }
    }
}

struct Reaper: System {
    func run(in world: inout World) {
        var commands = Commands()
        world.update(Health.self) { health, row in
            if health.current <= 0 { commands.despawn(row.entity) }
        }
        world.apply(commands)
    }
}

struct Tick: System {
    func run(in world: inout World) {
        world.resources[Clock.self].ticks += 1
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
- **`update`**: changes one or two component types in place across every matching entity,
  reading any others. This is the fast path for systems.
- **Change detection**: every component remembers when it was added and last changed.
  `query(…).changed(Position.self)` inside a system lists what changed since that system last
  ran; `.added(…)` lists what is new. Outside a schedule, pass a tick: `since: checkpoint`.
- **Events**: `world.send(Collision(…))` in one system, `world.readEvents(Collision.self,
  by: Damage.self)` in another. Each reader reads each event once; an `UpdateEvents` system at the
  start of a frame drops events older than the previous frame.
- **`Commands`**: spawns, despawns and insertions recorded during an update and applied after it.
- **`Resources`**: values the world holds once, such as a clock or the frame's input.
- **`Schedule`**: systems in the order written, adjusted by `after` and `before` constraints,
  and skipped when a `runIf { world in … }` condition does not hold.

Queries and updates of up to three types have overloads the compiler fully specializes; more types
go through a parameter pack.

## Modules

| Module | Holds |
|---|---|
| `WorldModule` | `World`, `Entity`, `Component`, `Resource`, queries, updates and `Commands` |
| `Systems` | `System` and `Schedule`, ordered with [Grafluent](https://github.com/Tyler-Keith-Thompson/Grafluent) |

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
