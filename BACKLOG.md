# Backlog

Features worth having, in the order they will be built. Each lands as one commit with tests,
docs and benchmarks where speed matters. Move an item to Done when it ships.

## Next

1. **Inferred system access.** A `@System` macro (swift-syntax) that reads `run(in:)` and
   derives its `Access` from the calls it can see: `update` and `query` type arguments,
   subscripts read or assigned, `resources[…]`, `send` and `readEvents`. Macros see syntax, not
   types, so anything it cannot classify (the world passed to another function, a generic type,
   a stored closure) makes it fall back to exclusive (`nil`) with a warning naming the call; an
   explicit `access` always wins. Pair it with a debug-build check that records the columns and
   resources a concurrent change actually touched and traps on undeclared reads, as writes
   already do. Needs swift-syntax in both build systems (`swift_compiler_plugin` in Bazel).

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
- Snapshots: `WorldSnapshot<each C>` is `Codable`; `World(restoring:)` keeps every handle.
- World equality: `==` on snapshots of `Equatable` components, independent of storage order.
- Parallel updates: `parallelUpdate` chunks entities across cores; `@Sendable` bodies keep it
  deterministic.
- Parallel schedules: `Access` declarations, `World.runConcurrently`, `Schedule.parallelRun`.
- Groups: EnTT-style owning groups; queries and updates over exactly the grouped types walk
  the packed front with no lookups.
