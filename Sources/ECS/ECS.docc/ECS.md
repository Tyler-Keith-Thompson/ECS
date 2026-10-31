# ``ECS``

An entity component system: entities, their components and resources in a value-type world, and
systems run on it in a declared order.

## Overview

A ``WorldModule/World`` holds entities and the components they hold, one sparse set per component
type, plus resources it holds once. It is a copy-on-write value, so copies are cheap and
independent. Systems read and change it with queries, in-place updates and deferred commands, and a
``Systems/Schedule`` runs them as though in the order written, adjusted by `after` and `before`
constraints, at the same time where they do not conflict. A ``SimulationModule/Simulation`` steps
a world frame by frame through schedules by label, with a fixed timestep and states.

Plain spellings trap on a stale entity or a missing component, like an array subscript; `checked`
spellings throw a typed error instead.

`import ECS` imports every module. Each module also has its own documentation and can be
imported on its own.

```swift
import ECS

struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }

var world = World()
let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
world.update(Position.self, reading: Velocity.self) { position, row in
    position.x += row.components.dx
    position.y += row.components.dy
}
print(world[Position.self, of: ball])  // Position(x: 1.0, y: 2.0)
```

## Topics

### Modules

- ``WorldModule``
- ``Systems``
- ``SimulationModule``
