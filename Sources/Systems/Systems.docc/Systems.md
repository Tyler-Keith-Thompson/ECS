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

## Topics

### Systems

- ``System``
- ``ScheduledSystem``
- ``UpdateEvents``

### Schedules

- ``Schedule``
- ``ScheduleBuilder``
- ``CyclicOrdering``
