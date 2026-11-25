# ECS

An entity component system for Swift, for games, simulations and anything else that updates many
similar things each step.

In an entity component system, the things your program tracks are **entities**: lightweight
handles that hold no data themselves. The data lives in **components**, plain value types such as
a position or a health bar, attached to entities. The behavior lives in **systems**, rules that run
over every entity holding a set of components. This package keeps each component type in a sparse
set, so reading, adding and removing a component take constant time, and it runs systems that don't
conflict at the same time.

The world that holds it all is a value, like an array: you can copy it for a snapshot, an undo step
or a rollback, and the copy shares storage until one side writes.

[Documentation](https://tyler-keith-thompson.github.io/ECS/documentation/)

## Installation

ECS requires Swift 6.3 and supports macOS 15, iOS 18, tvOS 18, watchOS 11 and visionOS 2
or later.

Add the package to your `Package.swift`:

```swift Package.swift
dependencies: [
    .package(url: "https://github.com/Tyler-Keith-Thompson/ECS", from: "0.0.1"),
],
```

Then add a product to your target, either the umbrella or individual modules:

```swift Package.swift
.target(name: "MyApp", dependencies: [
    .product(name: "ECS", package: "ECS"),
    // or, for example:
    // .product(name: "WorldModule", package: "ECS"),
]),
```

## Usage

Every Swift example in this README compiles and runs as a test in `Tests/ECSTests`, and the lines
marked `// Prints` are checked too.

The following example declares three components and two systems, spawns two entities, and runs
one step:

```swift
import ECS

// Components are plain value types.
struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }
struct Health: Component { var current: Int }

// Moves everything with a velocity.
@System
struct Movement {
    func run(_ movers: Update<Position>.Over<Velocity>) {
        movers { position, row in
            position.x += row.components.dx
            position.y += row.components.dy
        }
    }
}

// Despawns everything whose health has run out.
@System
struct Reaper {
    func run(_ living: Query<Health>, commands: inout Commands) {
        for (entity, health) in living where health.current <= 0 {
            commands.despawn(entity)
        }
    }
}

var world = World()
let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2), Health(current: 3))
let ghost = world.spawn(Health(current: 0))

let step = Schedule {
    Movement()
    Reaper()
}
step.run(on: &world)

print(world[Position.self, of: ball])
// Prints "Position(x: 1.0, y: 2.0)"
print(world.contains(ghost))
// Prints "false"
```

Each system states what it reads and writes through the types of its `run` method's parameters.
`Movement` writes `Position` and reads `Velocity`, and `Reaper` reads `Health`, so the schedule runs
them at the same time. The despawn `Reaper` records applies once both finish.

## Documentation

The [documentation](https://tyler-keith-thompson.github.io/ECS/documentation/) covers every module
and type. Start with these articles:

- [Getting Started with ECS](https://tyler-keith-thompson.github.io/ECS/documentation/ecs/gettingstarted):
  components, entities, systems, schedules and simulations, step by step.
- [WorldModule](https://tyler-keith-thompson.github.io/ECS/documentation/worldmodule): the world,
  [querying it](https://tyler-keith-thompson.github.io/ECS/documentation/worldmodule/queryingaworld),
  [reacting to changes](https://tyler-keith-thompson.github.io/ECS/documentation/worldmodule/reactingtochanges),
  [relations and hierarchies](https://tyler-keith-thompson.github.io/ECS/documentation/worldmodule/relatingentities),
  [disabled entities and prefabs](https://tyler-keith-thompson.github.io/ECS/documentation/worldmodule/disablingentitiesandusingprefabs),
  and [saving and loading](https://tyler-keith-thompson.github.io/ECS/documentation/worldmodule/savingandloadingworlds).
- [Systems](https://tyler-keith-thompson.github.io/ECS/documentation/systems):
  [declaring systems](https://tyler-keith-thompson.github.io/ECS/documentation/systems/declaringsystems),
  [scheduling them](https://tyler-keith-thompson.github.io/ECS/documentation/systems/schedulingsystems),
  and [driving a world from an app](https://tyler-keith-thompson.github.io/ECS/documentation/systems/drivingaworldfromanapp).
- [SimulationModule](https://tyler-keith-thompson.github.io/ECS/documentation/simulationmodule):
  frames, a fixed timestep and states.

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
| `just bench` | The benchmarks (`Benchmarks/README.md`) |
| `just generate` | An Xcode project from the Bazel graph, in `xcode/` |

`AGENTS.md` describes the layout, the workflow and the house rules in full.

## License

Apache 2.0. See `LICENSE`.
