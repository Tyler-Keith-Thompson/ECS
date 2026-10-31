# Backlog

Features worth having, in the order they will be built. Each lands as one commit with tests,
docs and benchmarks where speed matters. Move an item to Done when it ships.

## Next

1. **Systems declared by their parameters.** A system's `run` takes either the world or system
   parameters, and `@System` (a swift-syntax macro, the default spelling) connects either kind:

   ```swift
   @System
   struct LevelLoader {
       func run(in world: inout World) { … }        // runs alone
   }

   @System
   struct Movement {
       func run(
           _ movers: Update<Position>.Over<Velocity, AnyOf<Wind, Current>>.Where<Without<Frozen>>,
           _ time: ResourceReader<Time>
       ) {
           movers { position, row in
               let (velocity, (wind, current)) = row
               position.x += (velocity.dx + (wind?.force ?? 0) + (current?.force ?? 0)) * time.value.delta
           }
       }
   }
   ```

   - **Macro.** For a world-taking `run` it adds the `System` conformance with no access. For
     parameters it generates `access` from the parameter types and the `run(in:)` that fetches
     them, calls `run` and puts the writes back. It reads only the signature, never the body, so
     the access is exact. Hand-written `System` conformances keep working. Diagnostics with
     fix-its: the world mixed with parameters, the world not `inout`, a parameter that is not a
     system parameter, two parameters that conflict (when the names show it; otherwise a trap
     when the system is built), `inout` parameters or a `mutating` `run`, `async` or `throws`,
     no `run` or several.
   - **Parameters.** Each parameter type mirrors a `Query` value. `Query<…>` reads its terms
     (components and `AnyOf<…>`). `Update<A>`, `Update<A>.And<B>` and
     `Update<A>.And<B>.And<C>` write one to three types, each passed `inout`, optionally
     `.Over<…>` terms read alongside, as `world.update(_:over:)` does; every write level is
     fixed-arity, so the loops specialize. Both take `.Where<…>` filter types mirroring the
     filter values: `With<A>`, `Without<A>`, `Added<A>`, `Changed<A>` and `AnyOf<…>` of them.
     `ResourceReader<…>`, `ResourceWriter<…>`, `EventReader<…>`, `EventWriter<…>`, and
     `Commands`, which records structural changes without conflicting with anything.
     Parameters that write are reference types, so `run` takes them by value.
   - **Commands** apply at the end of the group their system ran in, buffer by buffer in written
     order, in both serial and parallel runs, so the two give the same world.
   - **Scheduling.** Replace grouping of neighbors with a dependency graph built from conflicts
     and `after` / `before` (Grafluent), running every system whose predecessors have finished.
     `run(on:)` runs in parallel wherever it can, with a serial mode for debugging; a system that
     takes the world runs alone.
   - **Checks.** A debug-build recorder of the columns and resources a concurrent system
     touched, trapping on undeclared reads as undeclared writes already trap; it also covers
     hand-written `access`.

   Settled in a prototype (branch `spike/system-parameters`): 300 systems over 300 types and one
   system of 300 parameters compile and run on macOS and Linux; type-checking stays in tens of
   milliseconds except for systems wider than about 200 types. Not possible in Swift today:
   per-arity overloads selected by a same-type requirement on a pack, labeled tuples as generic
   parameter lists, and a variable number of `inout` closure parameters; the design avoids all
   three. Needs swift-syntax in both build systems (`swift_compiler_plugin` in Bazel).

2. **Ambiguity detection.** Report pairs of systems in a schedule whose declared access conflicts
   but which no `after` / `before` orders, since their order then rests on how they were written.
   A schedule check returning a witness (`ambiguities() -> [Ambiguity]`), plus a debug-build
   warning when a schedule first runs.
3. **Required components.** A component names components it needs (`static var required`), and
   inserting it inserts the missing ones' defaults, transitively, in both the world and commands.
4. **Removal detection.** A per-reader list of entities that lost a component or were despawned
   since that reader last looked (`world.removed(Health.self, by: Reader.self)`), built on hooks
   and event places.
5. **Named schedules and states.** Schedules by label (`Startup`, `Update`, `FixedUpdate`) in an
   app-level runner, `FixedUpdate` on a fixed timestep with an accumulator, and a `State` value
   with `onEnter` / `onExit` / `onTransition` schedules and `inState` run conditions.
6. **System sets.** A named group of systems ordered and conditioned together with one `after`,
   `before` or `runIf`.
7. **Disabled entities and default filters.** A `Disabled` marker every query and update skips
   unless it asks for it (`.including(Disabled.self)`).
8. **Entity cloning and prefabs.** `world.clone(entity)` copies every component; a prefab entity
   is a template that queries skip and `spawn(from:)` copies.
9. **Column spans.** `Span` / `MutableSpan` access to a whole column for SIMD loops and C
   interop, marking every component changed once.
10. **Cached queries.** A query state that remembers a `Query`'s matching entities and keeps them
    current from structural changes, so a narrow query stops walking a large column.
11. **Relationships as pairs.** `(Relation, target)` components with queries over a relation's
    target or any target (`Pair<Targets, Wildcard>`), exclusive relations, and cleanup when a
    target despawns; the hierarchy becomes one relation.
12. **Observers on custom triggers.** `world.trigger(Explode(), on: entity)` with handlers that can
    propagate up the hierarchy, and observers for an entity starting or stopping to match a
    query.
13. **Indexes by value.** `world.index(Name.self)` keeps a map from a `Hashable` component's value
    to its entities, current through hooks.
14. **Scenes and a type registry.** Register component types once; save and load whole worlds
    without listing types per snapshot.
15. **Swift concurrency bridges.** Events and changes as an `AsyncSequence` (Afluent), and
    `@MainActor` systems run on the main actor by a schedule.
16. **Profiling.** Time per system per run, and the schedule's dependency graph as DOT.

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
- Queries as values: `Query` of components and `AnyOf` groups, `anyOf` filters, `query(_:)` and
  `update(_:over:)` writing one to three types; fixed-arity shapes generated by Bazel.
