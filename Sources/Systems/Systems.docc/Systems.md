# ``Systems``

Rules that run on a world, in the order written unless constrained otherwise.

## Overview

A ``System`` changes a world once per run. A ``Schedule`` lists systems in the order they run:
the order they are written, except that `after` and `before` constraints move a system up to run
just before the one that must follow it. Constraints that form a cycle trap, or throw
``CyclicOrdering`` from ``Schedule/init(checked:)``.

## Topics

### Systems

- ``System``
- ``ScheduledSystem``
- ``UpdateEvents``

### Schedules

- ``Schedule``
- ``ScheduleBuilder``
- ``CyclicOrdering``
