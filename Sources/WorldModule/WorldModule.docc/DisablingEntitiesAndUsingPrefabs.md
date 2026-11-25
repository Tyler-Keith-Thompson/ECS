# Disabling Entities and Using Prefabs

Take entities out of play without despawning them, and spawn copies of entities and templates.

## Overview

A game often keeps entities that shouldn't take part in a step: an enemy waiting off screen, or
the template every goblin is copied from. A world hides those entities from queries and updates
while keeping their components, and it can copy any entity into a new one.

### Disable an Entity

Insert ``Disabled`` into an entity to hide it from queries and updates. The entity stays live and
keeps its components, and reading it through its handle still works. A query or update reaches it
only when it reads or writes `Disabled`, names it in a filter, or allows it with
`.allowing(Disabled.self)`. Remove the mark to bring the entity back.

To make your own component types hide entities the same way, register them with
``World/registerDisablingComponent(_:)``.

Disabling hides an entity from queries and updates only. The world's ``World/count``,
``World/entities`` and the spans of ``World/withSpan(of:_:)`` still include it.

### Clone an Entity

``World/clone(_:)`` spawns a new entity holding a copy of every component of another. The copies
are new components, so they count as added and fire add and insert hooks. A clone keeps the
original's relations, so a clone of a child is its sibling, but the original's children aren't
cloned.

### Spawn from a Prefab

A *prefab* is an entity marked with ``Prefab`` that holds a ready-made set of components. Queries
and updates skip it, as they skip disabled entities, so the template never moves or takes damage
along with its copies. ``World/spawn(from:)`` copies a prefab without its mark, so the new entity
takes part like any other.

``Commands`` record clones and spawns from prefabs too, so a system can spawn copies during a
step. The following example spawns two goblins from a prefab through commands:

```swift
var world = World()
let goblin = world.spawn(Prefab(), Name(value: "goblin"), Health(current: 10))

var commands = Commands()
commands.spawn(from: goblin)
commands.spawn(from: goblin)
world.apply(commands)

print(world.query(Name.self).count)
// Prints "2"
print(world.count)
// Prints "3"
```

To keep a prefab outside any world, such as in a file, save it as a ``Scene`` and spawn its
entities into a world with `spawn(contentsOf:)`; see <doc:SavingAndLoadingWorlds>.
