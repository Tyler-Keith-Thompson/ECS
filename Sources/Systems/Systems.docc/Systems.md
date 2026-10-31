# ``Systems``

Rules that run on a world, in the order written unless constrained otherwise.

## Overview

A ``System`` changes a world once per run. A ``Schedule`` lists systems in the order they run:
the order they are written, except that `after` and `before` constraints move a system up to run
just before the one that must follow it. Constraints that form a cycle trap, or throw
``CyclicOrdering`` from ``Schedule/init(checked:)``.

A system that declares its ``System/access`` can run alongside the systems next to it that it
does not conflict with: ``Schedule/parallelRun(on:)`` gives the same world as
``Schedule/run(on:)``, using more cores.

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
