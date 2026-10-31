# Backlog

Features worth having, in the order they will be built. Each lands as one commit with tests,
docs and benchmarks where speed matters. Move an item to Done when it ships.

## Next

1. **Relationships.** `Parent` and `Children` kept consistent by the world: setting a parent
   updates the children, despawning a parent despawns its descendants, and queries can walk the
   hierarchy.
2. **Entity reservation.** `Commands.spawn` returns the entity it will create, so later commands
   in the same buffer can refer to it.
3. **Bundles.** A `Bundle` protocol for a named group of components spawned and inserted
   together, with a result builder for composing them.
4. **Observers.** Hooks run when a component of a type is added, changed or removed, for
   maintaining indexes and reacting to state without polling.
5. **Snapshots.** Saving a world to `Codable` data and loading it back, for components that are
   `Codable`, with entity handles preserved.
6. **World equality.** `==` on worlds whose components are `Equatable`, for determinism tests,
   replays and rollback checks.
7. **Parallel updates.** `update` split across cores for large worlds, with a deterministic
   result.
8. **Parallel schedules.** Systems that declare what they read and write, and a schedule that
   runs systems with disjoint access concurrently.
9. **Groups.** EnTT-style owning groups that keep several component types packed in the same
   order, for multi-type iteration with no lookups.

## Done

- Sparse-set world with copy-on-write, queries with filters, in-place updates, commands,
  resources.
- Schedules ordered by `after` / `before`.
- Tuple query rows: `for (entity, position, velocity) in world.query(...)`.
- Benchmarks with package-benchmark.
- Change detection: added and changed ticks per component, `.added` / `.changed` filters, and
  each system's previous run tracked by its schedule.
- Events: typed, double-buffered `Events<E>` resources, per-reader places, `UpdateEvents`.
- Run conditions: `runIf` on systems and schedules.
