# ``WorldModule/Commands``

## Topics

### Creating a Command Buffer

- ``init()``

### Inspecting a Command Buffer

- ``count``
- ``isEmpty``

### Spawning and Despawning Entities

- ``spawn(_:)``
- ``clone(_:)``
- ``spawn(from:)``
- ``despawn(_:)``

### Adding and Removing Components

- ``insert(_:into:)``
- ``remove(_:from:)``

### Changing the Hierarchy and Relations

- ``addChild(_:to:)``
- ``spawn(_:childOf:)``
- ``removeParent(of:)``
- ``relate(_:_:to:)``
- ``unrelate(_:_:from:)``

### Sending Events

- ``send(_:)``
- ``trigger(_:on:)``

### Changing Resources

- ``insert(resource:)``

### Recording Any Change

- ``record(_:)``

