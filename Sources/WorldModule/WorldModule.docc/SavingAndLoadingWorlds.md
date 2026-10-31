# Saving and Loading Worlds

Save a world's entities and components, restore them later, and spawn saved groups of entities
into other worlds.

## Overview

A ``World`` is a value, so keeping a copy in memory is as simple as assigning it to another
variable. To keep a world beyond the life of your program, such as in a save file, or to send it
somewhere else, encode it. WorldModule offers two ways to do that:

- A ``WorldSnapshot`` saves the components of the types you list each time you take one. It's the
  quickest way to save a few types, and to compare two worlds.
- A ``Scene`` saves the components and resources of the types a ``TypeRegistry`` names, so you
  list your types once. A scene can also be spawned into another world as new entities.

Both save every entity, live or stale, and the hierarchy (``ChildOf``). Neither saves hooks,
observers, caches, indexes or change ticks.

### Make Your Types Codable

Every component and resource type you save must conform to `Codable`. Swift synthesizes the
conformance for most types, so declaring it is usually enough:

```swift
extension Position: Codable, Equatable {}
extension Health: Codable {}
extension Name: Codable {}

struct Treasury: Resource, Codable { var gold: Int }
```

### Take a Snapshot

Call ``World/snapshot(_:)`` with the component types to save. The snapshot is `Codable`, so any
encoder can write it, and `World(restoring:)` rebuilds the world from it:

```swift
import Foundation

var world = World()
let knight = world.spawn(Name(value: "Knight"), Health(current: 10))
let data = try JSONEncoder().encode(world.snapshot(Name.self, Health.self))

let snapshot = try JSONDecoder().decode(WorldSnapshot<Name, Health>.self, from: data)
let restored = World(restoring: snapshot)
print(restored[Health.self, of: knight])
// Prints "Health(current: 10)"
```

Entity handles mean the same in the restored world as in the original, so `knight` still names
the knight. Components of types you didn't list are left out.

When every saved type is `Equatable`, so is the snapshot. Comparing two snapshots compares the
worlds they were taken of, which is useful for checking that a replay reproduces a recording:

```swift
var recorded = World()
let runner = recorded.spawn(Position(x: 0, y: 0))
recorded[Position.self, of: runner].x += 1

var replayed = World()
let replayedRunner = replayed.spawn(Position(x: 0, y: 0))
replayed[Position.self, of: replayedRunner].x += 1

print(replayed.snapshot(Position.self) == recorded.snapshot(Position.self))
// Prints "true"
```

### Save Whole Worlds with Scenes

Register the types your program saves in a ``TypeRegistry``, once, under names of your choosing.
Then ``World/scene(_:)`` saves every registered type a world holds. Decoding a scene needs the
same registry, passed in the decoder's `userInfo` under `CodingUserInfoKey.typeRegistry`:

```swift
import Foundation

var registry = TypeRegistry()
try registry.register(Name.self, named: "Name")
try registry.register(Health.self, named: "Health")
try registry.register(resource: Treasury.self, named: "Treasury")

var world = World()
world.resources.insert(Treasury(gold: 250))
let castle = world.spawn(Name(value: "Castle"))
let guardian = world.spawn(Name(value: "Guard"), Health(current: 12))
try world.addChild(guardian, to: castle)
let data = try JSONEncoder().encode(world.scene(registry))

let decoder = JSONDecoder()
decoder.userInfo[.typeRegistry] = registry
let restored = World(restoring: try decoder.decode(Scene.self, from: data))
print(restored.children(of: castle) == [guardian])
// Prints "true"
print(restored.resources[Treasury.self].gold)
// Prints "250"
```

The names identify the types in saved data. Choose names of your own rather than relying on the
default, the type's full name, so that saved data stays readable after you rename a type or its
module.

### Save Relations

A scene saves the hierarchy without being asked. To save another ``Relation``, make it `Codable`
and register its ``Targets`` component:

```swift
import Foundation

extension Likes: Codable {}

var registry = TypeRegistry()
try registry.register(Targets<Likes>.self, named: "Likes")

var world = World()
let alice = world.spawn()
let bob = world.spawn()
world.relate(alice, Likes(), to: bob)
let data = try JSONEncoder().encode(world.scene(registry))

let decoder = JSONDecoder()
decoder.userInfo[.typeRegistry] = registry
let restored = World(restoring: try decoder.decode(Scene.self, from: data))
print(restored.sources(Likes.self, of: bob) == [alice])
// Prints "true"
```

### Spawn Saved Entities into a World

Restoring a scene replaces a whole world. To add a scene's entities to an existing world instead,
as you would to place a saved enemy squad or a room of a level, call
``World/spawn(contentsOf:)``. Each of the scene's live entities is spawned as a new entity, and
the method returns the new entity for each of the scene's:

```swift
var registry = TypeRegistry()
try registry.register(Name.self, named: "Name")
try registry.register(Health.self, named: "Health")

var prefab = World()
let goblin = prefab.spawn(Name(value: "Goblin"), Health(current: 4))
let saved = prefab.scene(registry)

var world = World()
let first = world.spawn(contentsOf: saved)
let second = world.spawn(contentsOf: saved)
print(world.count)
// Prints "2"
print(first[goblin] == second[goblin])
// Prints "false"
```

Components that store entity handles must point at the new entities, not the scene's. Relations
and the hierarchy are updated for you. Conform your own components that store handles to
``MapEntities`` so that `spawn(contentsOf:)` can update them too.
