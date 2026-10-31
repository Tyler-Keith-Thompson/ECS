# ``ECS``

Build games and simulations from entities, the components they hold, and systems that update
them in a declared order.

## Overview

ECS is an entity component system for Swift. It suits any program that updates many similar
things each step, such as the bodies of a physics simulation or the characters of a game.

- Entities are lightweight handles. An ``/WorldModule/Entity`` holds no data of its own.
- Components are plain value types, such as a position or a velocity, attached to entities.
- A ``/WorldModule/World`` holds the entities and their components, along with *resources*,
  values the world holds once, such as a clock.
- Systems are rules that read and change the world through queries and updates, and a
  ``/Systems/Schedule`` runs them in the order you write, at the same time where they don't
  conflict.
- A ``/SimulationModule/Simulation`` runs a world frame by frame, with a fixed timestep and
  states.

A world is a copy-on-write value, like an array: copies are cheap and independent, so you can
keep one for a snapshot, an undo step or a rollback.

The following example, using the `Position` and `Velocity` components from
<doc:GettingStarted>, spawns a ball and moves it one step by its velocity:

```swift
import ECS

var world = World()
let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
world.update(Position.self, reading: Velocity.self) { position, row in
    position.x += row.components.dx
    position.y += row.components.dy
}
print(world[Position.self, of: ball])
// Prints "Position(x: 1.0, y: 2.0)"
```

`import ECS` imports every module. Each module also has its own documentation, and you can
import one on its own.

## Topics

### Essentials

- <doc:GettingStarted>

### Modules

- ``/WorldModule``
- ``/Systems``
- ``/SimulationModule``
