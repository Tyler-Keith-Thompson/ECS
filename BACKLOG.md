# Backlog

Features worth having, in the order they will be built. Each lands as one commit with tests,
docs and benchmarks where speed matters. Move an item to Done when it ships.

## Next

1. **Snapshots.** Saving a world to `Codable` data and loading it back, for components that are
   `Codable`, with entity handles preserved.
2. **World equality.** `==` on worlds whose components are `Equatable`, for determinism tests,
   replays and rollback checks.
3. **Parallel updates.** `update` split across cores for large worlds, with a deterministic
   result.
4. **Parallel schedules.** Systems that declare what they read and write, and a schedule that
   runs systems with disjoint access concurrently.
5. **Groups.** EnTT-style owning groups that keep several component types packed in the same
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
- Relationships: a parent and children per entity kept by the world, walks, cascading despawn.
- Entity reservation: `Commands.spawn` returns a handle later commands in the buffer resolve;
  `apply` returns the spawned entities.
- Bundles: the `Bundle` protocol and `BundleBuilder`; components are bundles of themselves.
- Observers, as component hooks: `onAdd`, `onInsert`, `onRemove`, run after the firing
  operation. In-place changes are left to change detection.
