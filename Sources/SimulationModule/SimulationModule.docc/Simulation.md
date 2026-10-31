# ``SimulationModule/Simulation``

## Topics

### Creating a Simulation

- ``init(_:fixedTimestep:maximumDelta:)``
- ``init(_:checkedFixedTimestep:maximumDelta:)``

### Adding Systems and States

- ``add(to:_:)``
- ``add(state:)``

### Running Frames

- ``update(elapsed:)``
- ``run(_:)``
- ``maximumDelta``

### Inspecting a Simulation

- ``world``
- ``schedules``
