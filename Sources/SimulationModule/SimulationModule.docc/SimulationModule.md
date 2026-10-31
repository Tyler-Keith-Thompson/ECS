# ``SimulationModule``

Run a world frame by frame, with schedules for startup, a fixed timestep and each frame, and
with states that switch systems on and off.

## Overview

A ``Simulation`` owns a world and a set of schedules, each named by a ``ScheduleLabel``. You add
systems to the schedules by label, then call ``Simulation/update(elapsed:)`` once a frame with the
time that passed. The simulation decides which schedules run:

- ``ScheduleLabel/startup`` runs once, before the first frame.
- ``ScheduleLabel/fixedUpdate`` runs once for every fixed timestep of time that has passed, so
  physics and other rate-sensitive rules advance by the same amount each run, however uneven the
  frames are.
- ``ScheduleLabel/update`` runs once a frame.

The examples throughout this module use these components, resources and systems:

```swift
struct Position: Component { var x: Double }
struct Velocity: Component { var dx: Double }
struct FixedSteps: Resource { var count = 0 }
enum GameState: States { case menu, playing, paused }

/// Moves each entity by its velocity over one fixed timestep.
@System
struct Physics {
    func run(_ movers: Update<Position>.Over<Velocity>, _ fixedTime: ResourceReader<FixedTime>) {
        let seconds = fixedTime.value.timestep / .seconds(1)
        movers { position, row in
            position.x += row.components.dx * seconds
        }
    }
}

/// Counts the runs of the schedule it is in.
@System
struct CountSteps {
    func run(_ steps: ResourceWriter<FixedSteps>) {
        steps.value.count += 1
    }
}

/// Spawns a ball at the origin.
@System
struct SpawnBall {
    func run(commands: inout Commands) {
        commands.spawn(Position(x: 0), Velocity(dx: 64))
    }
}
```

The following example runs `Physics` on a fixed timestep of 1/64 second, the default. A frame
of 50 milliseconds covers three whole timesteps, so the ball moves three times:

```swift
var world = World()
let ball = world.spawn(Position(x: 0), Velocity(dx: 64))

var simulation = Simulation(world)
simulation.add(to: .fixedUpdate) { Physics() }
simulation.update(elapsed: .milliseconds(50))

print(simulation.world[Position.self, of: ball])
// Prints "Position(x: 3.0)"
```

### States

A state type is a type, usually an enumeration, that conforms to ``States``: the screens of a
game, or the phases of a simulation. Add one to a simulation with
``Simulation/add(state:)``. The simulation keeps the current state in the ``CurrentState``
resource; to change it, a system sets ``NextState``, and the change applies at the start of the
next frame. Entering, leaving and moving between states run schedules of their own,
``ScheduleLabel/onEnter(_:)``, ``ScheduleLabel/onExit(_:)`` and
``ScheduleLabel/onTransition(from:to:)``, and ``inState(_:)`` makes a run condition that holds
only in one state.

The following example spawns a ball on entering the `playing` state and moves it only while the
game is in that state:

```swift
var simulation = Simulation()
simulation.add(state: GameState.menu)
simulation.add(to: .onEnter(GameState.playing)) { SpawnBall() }
simulation.add(to: .fixedUpdate) { Physics().runIf(inState(GameState.playing)) }

simulation.update(elapsed: .milliseconds(50))
print(simulation.world.count)
// Prints "0"

simulation.world.resources[NextState<GameState>.self].set(.playing)
simulation.update(elapsed: .milliseconds(50))
print(simulation.world.resources[CurrentState<GameState>.self].state)
// Prints "playing"
for (_, position) in simulation.world.query(Position.self) {
    print(position)  // Prints "Position(x: 3.0)"
}
```

## Topics

### Simulations

- ``Simulation``
- ``ScheduleLabel``
- ``NonPositiveDuration``

### Time

- ``Time``
- ``FixedTime``

### States

- ``States``
- ``CurrentState``
- ``NextState``
- ``inState(_:)``
