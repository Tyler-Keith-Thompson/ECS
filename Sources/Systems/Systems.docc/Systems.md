# ``Systems``

Rules that run on a world, in the order written unless constrained otherwise.

## Overview

A ``System`` changes a world once per run. A ``Schedule`` lists systems in the order they
take: the order they are written, except that `after` and `before` constraints move a system up
to run just before the one that must follow it. Constraints that form a cycle trap, or throw
``CyclicOrdering`` from ``Schedule/init(checked:)``.

``Schedule/run(on:)`` runs systems that neither conflict nor are ordered by a constraint at the
same time, in waves, and the world ends as it would running them one after another.
``Schedule/runSerially(on:)`` runs the same waves one system at a time. A system without a
``System/access`` runs alone.

Systems that conflict but that no constraint orders run in the order written.
``Schedule/ambiguities()`` lists them, so a test can keep a schedule free of them.

`@System` declares a system by its `run` method's parameters, whose types state what it reads
and writes, so the access is never written by hand:

```swift
@System
struct Movement {
    func run(_ movers: Update<Position>.Over<Velocity>.Where<Without<Frozen>>) {
        movers { position, row in position.x += row.components.dx }
    }
}
```

## Topics

### Systems

- ``System``
- ``ScheduledSystem``
- ``UpdateEvents``
- ``System()``

### System parameters

- ``SystemParameter``
- ``Update``
- ``ResourceReader``
- ``ResourceWriter``
- ``EventReader``
- ``EventWriter``

### Schedules

- ``Schedule``
- ``ScheduleBuilder``
- ``CyclicOrdering``
- ``Ambiguity``
