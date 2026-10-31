# ``SimulationModule``

A world and its schedules by label, stepped one frame at a time.

## Overview

A ``Simulation`` holds a world and schedules named by ``ScheduleLabel``. Each frame it updates
the world's events, applies pending state changes, runs the ``ScheduleLabel/fixedUpdate``
schedule once per fixed timestep elapsed and runs the ``ScheduleLabel/update`` schedule;
``ScheduleLabel/startup`` runs before the first frame.

A state type (``States``) is a value the simulation is in, kept as the ``CurrentState`` resource
and changed through ``NextState``. Entering, leaving and moving between states run schedules of
their own, and ``inState(_:)`` makes a run condition from one.

## Topics

### Simulations

- ``Simulation``
- ``ScheduleLabel``
- ``Time``
- ``FixedTime``
- ``NonPositiveDuration``

### States

- ``States``
- ``CurrentState``
- ``NextState``
- ``inState(_:)``
