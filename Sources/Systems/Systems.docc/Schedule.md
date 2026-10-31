# ``Systems/Schedule``

## Topics

### Creating a Schedule

- ``init(_:)``
- ``init(checked:)``
- ``ScheduleBuilder``
- ``CyclicOrdering``

### Running Systems

- ``run(on:)``
- ``runSerially(on:)``

### Ordering and Conditioning Every System

- ``after(_:)``
- ``before(_:)``
- ``inSet(_:)``
- ``ambiguous(with:)``
- ``runIf(_:)``

### Inspecting a Schedule

- ``systems``
- ``names``
- ``ambiguities()``
- ``Ambiguity``
- ``writeDOT(to:)``
