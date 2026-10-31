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
replay or a comparison takes one assignment.

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
`index(_:)` on ``World``; `lookup(_:)` finds the entities holding a value.

### Deferring Changes

- ``Commands``

### Working with Resources

- ``Resources``

### Detecting Changes and Removals

- ``ChangeTick``
- ``RemovedComponent``

### Disabling Entities and Using Prefabs

- ``Disabled``
- ``Prefab``

### Building Hierarchies

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
- ``MapEntities``

### Running Changes Concurrently

- ``Access``
- ``ConcurrentChange``

### Errors

- ``StaleEntity``
- ``MissingComponent``
- ``MissingResource``
