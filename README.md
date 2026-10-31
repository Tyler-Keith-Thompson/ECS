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

[Documentation](https://tyler-keith-thompson.github.io/ECS/documentation/), including a
*Getting Started* walkthrough.

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

Every Swift example in this README compiles and runs as a test in `Tests/ECSTests`, so it cannot
drift from the code. The lines marked `// Prints` are checked too.

The following example declares a few components and three systems, spawns three entities, and runs
one step:

```swift
import ECS

// Components are plain value types.
struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }
struct Health: Component { var current: Int }
struct Frozen: Component {}

// A resource is a value the world holds once.
struct Clock: Resource { var ticks = 0 }

// Moves everything with a velocity, unless it is frozen.
@System
struct Movement {
    func run(_ movers: Update<Position>.Over<Velocity>.Where<Without<Frozen>>) {
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

// Counts the steps.
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

let step = Schedule {
    Reaper().after(Movement.self)
    Movement()
    Tick()
}
step.run(on: &world)

print(step.names)
// Prints "["Movement", "Reaper", "Tick"]"
print(world[Position.self, of: ball])
// Prints "Position(x: 1.0, y: 2.0)"
print(world[Position.self, of: wall])
// Prints "Position(x: 5.0, y: 0.0)"
print(world.contains(ghost))
// Prints "false"
print(world.resources[Clock.self])
// Prints "Clock(ticks: 1)"
```

Each system says what it reads and writes through the types of its `run` method's parameters, so
the schedule knows that `Movement` and `Tick` touch different data and can run at the same time.
`Reaper().after(Movement.self)` moves `Reaper` after `Movement`, and the despawn it records applies
once its wave of systems finishes.

## A Tour of the Pieces

### The world and its entities

- **`Entity`** is a slot and a generation. When an entity is despawned, its handle goes stale
  instead of naming whatever reuses the slot.
- **`World`** holds entities and their components: `spawn`, `despawn`, `insert` and `remove` them,
  and read or change one component in place with `world[Position.self, of: entity]`. Plain
  spellings trap on a stale entity or a missing component, like an array subscript; `checked`
  spellings throw a typed error instead.
- **Resources** are values the world holds once, such as a clock or the frame's input:
  `world.resources.insert(Clock())`.
- **Bundles** group components that go together. A `Bundle` lists them in a `body`, which can use
  `if` and `switch`, and you spawn, insert and remove it as one. Every component is a bundle of
  itself.
- **Required components**: a component lists the others it needs in `static var required`, and
  spawning or inserting it adds each one the entity lacks, transitively. Components you pass
  explicitly win.
- **`Commands`** record spawns, despawns and insertions during an update, to apply after it.
  `commands.spawn(…)` returns a handle that later commands in the same buffer can name.

### Queries and updates

- **`query`** is a lazy view of the entities holding every listed type, narrowed with `with` and
  `without`. Each row is a tuple, `(entity, component, …)`. A view is a snapshot of the world, so
  writing to the world while iterating is safe.
- **`Query`** is a query as a value, kept and run against any world. `AnyOf<Wind, Current>`
  matches entities holding at least one of its types and yields a tuple of optionals, and
  `.anyOf(…)` filters pass entities meeting at least one condition.
- **`update`** changes one or two component types in place across every matching entity, reading
  others, or one to three types over a `Query`. It is the fast path for systems, and
  `parallelUpdate` spreads the same work across cores with the same result.

The following example moves everything that has wind or a current, except what is anchored:

```swift
struct Wind: Component { var speed: Double }
struct Current: Component { var speed: Double }
struct Anchored: Component {}

var world = World()
let raft = world.spawn(Position(x: 0, y: 0), Wind(speed: 1), Current(speed: 2))
let kite = world.spawn(Position(x: 0, y: 0), Wind(speed: 3))
let buoy = world.spawn(Position(x: 0, y: 0), Current(speed: 4), Anchored())
let rock = world.spawn(Position(x: 0, y: 0))

let drifting = Query(AnyOf<Wind, Current>.self).without(Anchored.self)
world.update(Position.self, over: drifting) { position, row in
    let (wind, current) = row.components
    position.x += (wind?.speed ?? 0) + (current?.speed ?? 0)
}

print(world[Position.self, of: raft].x)
// Prints "3.0"
print(world[Position.self, of: kite].x)
// Prints "3.0"
print(world[Position.self, of: buoy].x)
// Prints "0.0"
print(world[Position.self, of: rock].x)
// Prints "0.0"
```

Queries and updates of up to three types have overloads the compiler fully specializes; more types
go through a parameter pack. To go faster still:

- **Groups**: `world.group(Position.self, Velocity.self)` keeps two or more types packed in the
  same order, so queries and updates over exactly those types make no lookups.
- **Cached queries**: `world.cache(Query(Position.self).without(Sleeping.self))` keeps the entities
  a query matches up to date, so a visit implying it walks only those rather than a whole column.
- **Indexes**: `world.index(Name.self)` maps each value of a `Hashable` component to its entities,
  so `world.lookup(Name("bob"))` skips the walk.
- **Column spans**: `world.withSpan(of: Health.self) { entities, health in … }` lends a component
  type's storage as `Span`s for vectorized loops and C calls; `withMutableSpan` writes in place
  and marks every component changed.

### Noticing changes

- **Change detection**: every component remembers when it was added and last changed.
  `query(…).changed(Position.self)` inside a system lists what changed since that system last ran,
  and `.added(…)` lists what is new. Outside a schedule, pass a tick: `since: checkpoint`.
- **Removal detection**: `world.removed(Health.self, by: Healthbars.self)` lists the entities that
  lost a `Health` since that reader last asked, by removal or despawn; a system takes
  `RemovedComponents<Health>`.
- **Hooks**: `world.onAdd(Name.self) { world, entity in … }`, `onInsert` and `onRemove` run after
  the operation that fired them, for keeping indexes without polling. Given a `Query`, `onAdd` and
  `onRemove` run when an entity starts or stops matching it.
- **Observers**: `world.observe(Explode.self, on: barrel) { world, trigger in … }` runs when
  `world.trigger(Explode(), on: barrel)` is called. Events that propagate move up the hierarchy
  until an observer stops them.
- **Events**: `world.send(Collision(…))` in one system, `world.readEvents(Collision.self,
  by: Damage.self)` in another. Each reader reads each event once, and an `UpdateEvents` system at
  the start of a frame drops events older than the previous frame.
- **Streams**: `ForwardEvents(to: continuation)` and `ForwardChanges(to: continuation)` are systems
  that yield new events, or added and changed components, to an `AsyncStream`, so code outside the
  schedule can `for await` them.

### Relations and hierarchy

- **Relations**: `world.relate(alice, Likes(), to: bob)` adds a pair; `targets(Likes.self, of:)`
  and `sources(Likes.self, of:)` read it both ways, and `.related(Likes.self, to: bob)` visits only
  bob's sources. Relations can be exclusive, carry values, and despawn their sources with their
  target.
- **Hierarchy**: `try world.addChild(turret, to: ship)`; `parent(of:)`, `children(of:)`,
  `ancestors(of:)` and `descendants(of:)` walk it, and despawning an entity despawns its
  descendants. The hierarchy is the `ChildOf` relation, so `.related(ChildOf.self, to: ship)`
  queries children and `.without(Targets<ChildOf>.self)` finds roots.

### Templates, saving and loading

- **Disabled entities**: `world.insert(Disabled(), into: enemy)` keeps the entity and its
  components but hides it from queries and updates, unless they read `Disabled`, name it in a
  filter or say `.allowing(Disabled.self)`. `registerDisablingComponent` adds types that hide
  entities the same way.
- **Cloning and prefabs**: `world.clone(entity)` spawns a copy of every component, and
  `world.spawn(from: goblin)` copies an entity marked `Prefab`, a template queries skip, without the
  mark. `Commands` records both.
- **Snapshots**: `world.snapshot(Position.self, Velocity.self)` is `Codable`, and
  `World(restoring:)` rebuilds the world with every entity handle unchanged. Snapshots of
  `Equatable` components compare with `==`, which is how to compare two worlds.
- **Scenes**: register component and resource types once in a `TypeRegistry`;
  `world.scene(registry)` is `Codable` and saves every registered type, and decoding takes the
  registry from the decoder's `userInfo[.typeRegistry]`. `world.spawn(contentsOf: scene)` adds a
  scene's entities to a world as new ones, such as a saved prefab; components conforming to
  `MapEntities` are pointed at the new entities.

### Systems and schedules

- **`@System`** declares a system by its `run` method's parameters, whose types state what it reads
  and writes:
  - `Query<…>` and `Query<…>.Where<…>` read components, and `Update<A>.And<B>.Over<…>.Where<…>`
    writes them.
  - `ResourceReader`, `ResourceWriter`, `EventReader`, `EventWriter` and `RemovedComponents` reach
    resources, events and removals.
  - `inout Commands` queues structural changes that apply after the system's wave.
  - The filter types `With`, `Without`, `Added`, `Changed`, `Allows` and `AnyOf` mirror the filter
    values.

  Parameters that conflict are a compile-time error. A `run(in world: inout World)` makes a system
  that may change anything. A `@MainActor` type or `run` makes a `MainActorSystem`, which a
  schedule run on the main actor runs there, after the other systems of its wave.
- **`Schedule`** runs systems in the order written, adjusted by `after` and `before` constraints,
  and skips a system when its `runIf { world in … }` condition does not hold. `run(on:)` runs
  systems that neither conflict nor are ordered at the same time, in waves, with the result running
  them in order gives; `runSerially(on:)` runs the same waves one system at a time.
- **Access**: a system's access comes from its parameters, or from `access` declared by hand; a
  system without one runs alone. In debug builds, a system that reaches a type its access does not
  list traps. `ambiguities()` lists conflicting systems no constraint orders, whose order rests on
  how they were written.
- **System sets**: a `SystemSet` (`enum Physics: SystemSet {}`) names a group. Systems join it with
  `inSet`, a nested `Schedule { … }` takes `inSet`, `after`, `before` and `runIf` for all its
  systems, and `after(Physics.self)` orders after every system in it.
- **Profiling**: with a `SystemProfile` resource in the world, schedules record each system's runs
  and times, and `writeDOT(to:)` draws a schedule's dependency graph for Graphviz.

### Simulations

A **`Simulation`** holds a world and schedules by label, and you advance it with
`update(elapsed:)` once a frame. `.startup` runs before the first frame; then each frame runs
`.fixedUpdate` once per fixed timestep elapsed, and `.update` once. A `States` type
(`enum GameState: States { … }`) runs `.onEnter`, `.onExit` and `.onTransition` schedules when a
system sets `NextState`, and `inState(…)` is a run condition.

The following example runs `Movement` on a fixed timestep of 10 milliseconds. A 30-millisecond
frame covers three timesteps, so the ball moves three times:

```swift
var world = World()
let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))

var simulation = Simulation(world, fixedTimestep: .milliseconds(10))
simulation.add(to: .fixedUpdate) { Movement() }
simulation.update(elapsed: .milliseconds(30))

print(simulation.world[Position.self, of: ball])
// Prints "Position(x: 3.0, y: 6.0)"
```

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
