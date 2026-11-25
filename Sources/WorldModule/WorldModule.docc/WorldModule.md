# ``WorldModule``

Store the state of a game or simulation as entities and components, and read and change it with
queries, updates, and commands.

## Overview

WorldModule is built around a ``World``, a value that holds everything your game or simulation
knows. The world organizes that state with a few simple ideas:

- An **entity** is one thing in the world, such as a ball, a player or a particle. It has no data
  of its own; you refer to it by its handle, an ``Entity``.
- A **component** is a plain value that an entity holds, such as a position or a health total.
  Any type that conforms to ``Component`` can be a component, and an entity holds at most one
  component of each type.
- A **resource** is a value the world holds once, outside any entity, such as a clock or a score.
  Any type that conforms to ``Resource`` can be a resource.

The examples throughout this module's documentation use these components:

```swift
struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }
struct Health: Component { var current: Int }
struct Frozen: Component {}
struct Name: Component, Hashable { var value: String }
```

### Spawn Entities and Work with Their Components

Spawn an entity with the components it starts with. The world returns the entity's handle, which
you use to read and change its components:

```swift
var world = World()
let hero = world.spawn(Name(value: "Ada"), Position(x: 0, y: 0), Health(current: 100))

world[Health.self, of: hero].current -= 30
world.insert(Velocity(dx: 1, dy: 0), into: hero)
world.remove(Position.self, from: hero)

print(world[Health.self, of: hero].current)
// Prints "70"
```

An entity's handle is a slot and a generation. Once the entity is despawned, its handle is
*stale*, and it never names an entity that reuses the slot.

Like an array subscript, the plain spellings trap when the entity is stale or doesn't hold the
component. Each has a `checked` spelling that throws a typed error instead, such as
``World/subscript(checked:of:)`` and ``World/despawn(checked:)``. For a component an entity may
or may not hold, use the optional subscript, `world[Velocity?.self, of: hero]`, which reads `nil`
for a missing component and removes the component when you assign `nil`.

### Group Components in Bundles

A ``Bundle`` names a set of components that go together, such as everything a ship starts with,
so you can spawn, insert and remove them as one. A bundle lists its components in its `body`,
which can use `if` and `switch`. Every component is a bundle of itself, so you can pass a single
component wherever a bundle is expected.

A component can also list the components it needs in its static `required` property. Spawning
or inserting it adds each required component the entity lacks, and whatever those require in
turn, while components you pass explicitly keep their values. See ``Component`` for an example.

### Query and Update Many Entities

Most of the work in a game applies to every entity that holds some set of components: every
entity with a position and a velocity moves, every entity with health can take damage. A query
visits those entities and reads their components, and an update changes one component of each in
place:

```swift
var world = World()
world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
world.spawn(Position(x: 5, y: 5), Velocity(dx: 0, dy: -1), Frozen())

world.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, row in
    position.x += row.components.dx
    position.y += row.components.dy
}

var coordinates: [(Double, Double)] = []
for (_, position) in world.query(Position.self) {
    coordinates.append((position.x, position.y))
}
print(coordinates)
// Prints "[(1.0, 0.0), (5.0, 5.0)]"
```

Filters such as `.without(Frozen.self)` narrow which entities a query or update visits. To learn
more, see <doc:QueryingAWorld>.

### Respond to Changes

A world records when each component was added and last changed, and which entities lost a
component. Hooks and observers run code as changes happen, and events carry messages from the
code that sends them to the code that reads them later. To learn more, see
<doc:ReactingToChanges>.

### Link Entities

Relations link one entity to others, such as a unit that likes another, and the hierarchy makes
trees of parents and children that despawn together. To learn more, see <doc:RelatingEntities>.

### Defer Structural Changes with Commands

While a query or update is visiting entities, you can't spawn or despawn entities or add and
remove their components. Record those changes in ``Commands`` instead, and apply them when the
visit is over:

```swift
var world = World()
world.spawn(Health(current: 0))
world.spawn(Health(current: 40))

var commands = Commands()
for (entity, health) in world.query(Health.self) where health.current <= 0 {
    commands.despawn(entity)
}
world.apply(commands)

print(world.count)
// Prints "1"
```

### Keep World-Wide State in Resources

A resource holds state that belongs to the whole world rather than to any entity:

```swift
struct Elapsed: Resource { var seconds: Double }

var world = World()
world.resources.insert(Elapsed(seconds: 0))
world.resources[Elapsed.self].seconds += 0.5

print(world.resources[Elapsed.self].seconds)
// Prints "0.5"
```

### Copy Worlds Freely

A world is a value: assigning it to another variable makes an independent copy. Copies share
storage until one of them changes, so copying is cheap, and keeping an earlier state for undo, a
replay or a comparison takes one assignment. To keep a world beyond the life of your program,
save it; see <doc:SavingAndLoadingWorlds>.

## Topics

### Essentials

- ``World``
- ``Entity``
- ``Component``
- ``Resource``

### Grouping Components

- ``Bundle``
- ``BundleBuilder``
- ``TupleBundle``
- ``EitherBundle``

### Querying and Updating Entities

- <doc:QueryingAWorld>
- ``Query``
- ``QueryView``
- ``EntityQueryView``
- ``QueryRow``
- ``QueryTerm``
- ``AnyOf``
- ``EntitiesView``

### Filtering Queries

- ``QueryFilter``
- ``FilterTerm``
- ``With``
- ``Without``
- ``Added``
- ``Changed``
- ``Allows``

### Speeding Up Queries

- ``GroupError``

Groups are made with `group(_:)`, cached queries with `cache(_:)` and indexes by value with
`index(_:)` on ``World``; `lookup(_:)` finds the entities holding a value, and
`lookup(_:equals:)` the entities whose property at a key path equals one.

### Deferring Changes

- ``Commands``

### Working with Resources

- ``Resources``

### Detecting Changes and Removals

- <doc:ReactingToChanges>
- ``ChangeTick``
- ``RemovedComponent``

### Disabling Entities and Using Prefabs

- <doc:DisablingEntitiesAndUsingPrefabs>
- ``Disabled``
- ``Prefab``

### Building Hierarchies

- <doc:RelatingEntities>
- ``ChildOf``
- ``AncestorsView``
- ``DescendantsView``
- ``CyclicHierarchy``
- ``HierarchyError``

### Relating Entities

- ``Relation``
- ``Targets``
- ``CleanupAction``

### Sending Events

- ``Event``
- ``Events``
- ``EventsView``

### Reacting to Changes with Hooks and Observers

- ``EntityEvent``
- ``Trigger``

Hooks are registered with `onAdd`, `onInsert` and `onRemove` on ``World``, for a component type
or a query. Observers are registered with `observe`.

### Saving and Loading Worlds

- <doc:SavingAndLoadingWorlds>
- ``WorldSnapshot``
- ``Scene``
- ``TypeRegistry``
- ``TypeRegistryError``
- ``TypeRegistryLookupError``
- ``MapEntities``

### Running Changes Concurrently

- ``Access``
- ``ConcurrentChange``

### Errors

- ``StaleEntity``
- ``MissingComponent``
- ``MissingResource``
