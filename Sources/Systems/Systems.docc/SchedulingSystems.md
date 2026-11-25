# Scheduling Systems

Order the systems of a schedule, run them only when a condition holds, and find out how a
schedule runs them.

## Overview

A ``Schedule`` lists the systems of one frame or step. When it runs, it decides the order from
what you wrote and the constraints you added, and it runs the systems that can't affect one
another at the same time.

### Order Systems

Systems run in the order you write them, adjusted by ordering constraints. `after(_:)` moves a
system after another, and `before(_:)` moves it before one; every other system keeps its written
place. A constraint that names a type with no system in the schedule is ignored. Constraints that
form a cycle trap, and ``Schedule/init(checked:)`` throws ``CyclicOrdering`` instead, for systems
or constraints that come from configuration.

### Run Systems Conditionally

`runIf(_:)` skips a system unless a condition on the world holds, such as the world holding no
`Paused` resource. On a nested schedule, it applies to each of the nested schedule's systems. Each
system checks its conditions at the start of the wave it runs in, so a system that changes what
a condition reads affects the systems in later waves. A condition must read only what each
system's access lists.

### Understand Waves

Two systems *conflict* when one writes a type the other reads or writes, or when either has no
``System/access``. ``Schedule/run(on:)`` runs the systems in *waves*: each wave holds the systems
whose earlier conflicting and ordered systems have run, and its systems run at the same time. The
commands systems queue apply when their wave finishes, so a system in the same wave doesn't see
another's spawns, despawns or inserts. To see them, order it after the system that queued them.

The world ends as though the systems had run one after another, in order. ``Schedule/runSerially(on:)``
runs the same waves one system at a time, with the same result. Use it to step through a system in
a debugger, or to rule out running at the same time as the cause of a problem.

A system's access comes from its parameters, with the ``System()`` macro, or from an `access`
you declare by hand. A system without one may change anything, so it runs alone. In debug
builds, a system that reaches a type its access doesn't list traps, so run a schedule's tests in
debug.

### Find Unordered Conflicts

When two conflicting systems aren't ordered by any constraint, the order they run in rests only
on how they happen to be written, which a later edit can change by accident.
``Schedule/ambiguities()`` lists those pairs. Order each pair, or mark it with
``ScheduledSystem/ambiguous(with:)`` when either order is right, and check in a test that the
list stays empty.

### Group Systems into Sets

A ``SystemSet`` names a group of systems, so a constraint can refer to all of them at once.
Declare one as an empty enumeration. A system joins it with `inSet(_:)`, and a nested schedule
takes `inSet(_:)`, `after(_:)`, `before(_:)` and `runIf(_:)` for all of its systems. Every system
type is a set too, holding each system of that type.

The following schedule groups gravity and movement into a physics set that doesn't run while
the game is paused, and scores after every physics system:

```swift
let frame = Schedule {
    Schedule {
        Gravity()
        Movement().after(Gravity.self)
    }
    .inSet(Physics.self)
    .runIf { world in !world.resources.contains(Paused.self) }
    Scoring().after(Physics.self)
}
print(frame.names)
// Prints "["Gravity", "Movement", "Scoring"]"
print(frame.ambiguities().isEmpty)
// Prints "true"
```

### Profile a Schedule

Insert a ``SystemProfile`` resource into a world, and every schedule that runs on it records each
system's runs and times. ``Schedule/writeDOT(to:)`` writes a schedule's dependency graph in the
DOT language, so Graphviz can draw why systems run in the order they do and which can run at the
same time.
