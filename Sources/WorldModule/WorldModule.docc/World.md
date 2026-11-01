# ``WorldModule/World``

## Topics

### Creating a World

- ``init()``

### Spawning and Despawning Entities

- ``spawn(_:)-2slwa``
- ``spawn(_:)-13jpz``
- ``spawn(_:)-5h8u``
- ``spawn(_:_:)``
- ``spawn(_:_:_:)``
- ``despawn(_:)``
- ``despawn(checked:)``

### Inspecting Entities

- ``count``
- ``isEmpty``
- ``entities``
- ``contains(_:)``

### Reading and Writing Components

- ``subscript(_:of:)->C``
- ``subscript(_:of:)->C?``
- ``subscript(checked:of:)``
- ``contains(_:in:)``
- ``count(of:)``

### Adding Components

- ``insert(_:into:)-70968``
- ``insert(_:into:)-8fkgl``
- ``insert(_:into:)-3ah54``
- ``insert(_:_:into:)``
- ``insert(_:_:_:into:)``
- ``insert(_:checkedInto:)``

### Removing Components

- ``remove(_:from:)-6y3q5``
- ``remove(_:checkedFrom:)-2af30``
- ``remove(_:from:)-9j0yg``
- ``remove(_:checkedFrom:)-9ksld``

### Cloning Entities and Spawning from Prefabs

- ``clone(_:)``
- ``clone(checked:)``
- ``spawn(from:)``
- ``spawn(checkedFrom:)``

### Querying Entities

- ``query(_:)-zacg``
- ``query(_:_:)``
- ``query(_:_:_:)``
- ``query(_:)-3e8od``
- ``query(_:)-4yi98``
- ``query()``

### Updating Components in Place

- ``update(_:reading:where:body:)-41hgj``
- ``update(_:reading:where:body:)-7eor``
- ``update(_:reading:_:where:body:)``
- ``update(_:reading:_:_:where:body:)``
- ``update(_:_:reading:where:body:)-4hvwu``
- ``update(_:_:reading:where:body:)-4u5t6``
- ``update(_:_:reading:_:where:body:)``
- ``update(_:_:reading:_:_:where:body:)``
- ``update(_:_:_:reading:where:body:)-1eb26``
- ``update(_:_:_:reading:where:body:)-5likl``
- ``update(_:_:_:reading:_:where:body:)``
- ``update(_:_:_:reading:_:_:where:body:)``
- ``update(_:over:body:)``
- ``update(_:_:over:body:)``
- ``update(_:_:_:over:body:)``

### Updating Components in Parallel

- ``parallelUpdate(_:reading:where:minimumChunk:body:)-69of8``
- ``parallelUpdate(_:reading:where:minimumChunk:body:)-59o00``
- ``parallelUpdate(_:reading:_:where:minimumChunk:body:)``
- ``parallelUpdate(_:reading:_:_:where:minimumChunk:body:)``

### Reaching Component Storage Directly

- ``withSpan(of:_:)``
- ``withMutableSpan(of:_:)``

### Speeding Up Queries

- ``group(_:)``
- ``group(checked:)``
- ``cache(_:)``
- ``index(_:)-u1gw``
- ``index(_:)-2gtfg``
- ``lookup(_:)``
- ``lookup(_:equals:)``
- ``index(ordered:)``
- ``lookup(_:in:)``
- ``entities(sortedBy:)``

### Disabling Entities

- ``registerDisablingComponent(_:)``

### Building a Hierarchy

- ``addChild(_:to:)``
- ``addChild(_:checkedTo:)``
- ``spawn(_:childOf:)``
- ``spawn(_:checkedChildOf:)``
- ``removeParent(of:)``
- ``removeParent(checkedOf:)``
- ``parent(of:)``
- ``parent(checkedOf:)``
- ``children(of:)``
- ``children(checkedOf:)``
- ``ancestors(of:)``
- ``ancestors(checkedOf:)``
- ``descendants(of:)``
- ``descendants(checkedOf:)``

### Relating Entities

- ``relate(_:_:to:)``
- ``relate(_:_:checkedTo:)``
- ``unrelate(_:_:from:)``
- ``unrelate(_:_:checkedFrom:)``
- ``targets(_:of:)``
- ``targets(_:checkedOf:)``
- ``sources(_:of:)``
- ``sources(_:checkedOf:)``

### Working with Resources

- ``resources``

### Applying Commands

- ``apply(_:)``
- ``queue(_:)``
- ``hasQueuedCommands``
- ``applyQueuedCommands()``

### Sending and Reading Events

- ``send(_:)``
- ``events(_:)``
- ``readEvents(_:by:)``
- ``updateEvents()``

### Responding to Component Changes with Hooks

- ``onAdd(_:perform:)-27g0l``
- ``onInsert(_:perform:)``
- ``onRemove(_:perform:)-2t2p``
- ``onAdd(_:perform:)-8d74u``
- ``onRemove(_:perform:)-5cn3d``
- ``removeHooks(of:)``

### Observing Entity Events

- ``observe(_:perform:)``
- ``observe(_:on:perform:)``
- ``trigger(_:on:)``
- ``trigger(_:checkedOn:)``

### Detecting Changes

- ``changeTick``
- ``advanceChangeTick()``
- ``lastRun``
- ``trackChanges(of:)``

### Detecting Removals

- ``trackRemovals(of:)``
- ``removed(_:by:)``

### Saving and Restoring

- ``snapshot(_:)``
- ``init(restoring:)-6alog``
- ``scene(_:)``
- ``init(restoring:)-7m7do``
- ``spawn(contentsOf:)``

### Running Changes Concurrently

- ``runConcurrently(_:)``
