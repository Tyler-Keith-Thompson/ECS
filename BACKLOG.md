# Backlog

Features worth having, in the order they will be built. Each lands as one commit with tests,
docs and benchmarks where speed matters. Move an item to Done when it ships.

## Next

1. **Queries as values, with `AnyOf`.** A `Query` describes a selection without a world: its
   terms are components and `AnyOf<…>` groups, and filters (`.with`, `.without`, `.added`,
   `.changed`) chain on it. Each type is named once.

   ```swift
   let movers = Query(Position.self, Velocity.self, AnyOf<Wind, Current>.self)
       .without(Frozen.self)

   for (entity, position, velocity, (wind, current)) in world.query(movers) { … }
   world.update(Position.self, over: movers) { position, row in … }
   ```

   - **Terms.** A component term matches entities holding it and yields its value. `AnyOf<A, B, …>`
     matches entities holding at least one of its types and yields a tuple of optionals, one
     per type, so a row keeps each group as a nested tuple (`for` patterns take it apart;
     closures receive it whole). Any number of terms and of `AnyOf` types.
   - **Filters.** `.with`, `.without`, `.added`, `.changed`, and `.anyOf(…)` of filters, which
     passes entities meeting at least one (`.anyOf(.changed(A.self), .without(B.self))`).
     Terms and filters are ANDed, so any condition on which components an entity holds can be
     written as an AND of ORs; `added` and `changed` cannot be negated.
   - **Speed.** Fixed-arity versions for one to three terms and for `AnyOf` of two to four
     types, each building its `Reader` at fixed arity, with the parameter-pack versions as the
     general fallback, as `world.query` and `world.update` have today. Benchmarks for each
     arity, against the existing spellings.
   - **Updates.** `world.update(_:over:)` for one to three written types visits the query's
     entities and passes its row alongside; a query that also reads a written type traps, as
     `reading:` does today.
   - The query value is `Sendable`, `Hashable` and holds no world, so systems and system
     parameters can store it. `QueryFilter` becomes the query's filter part.
   - Settled in a prototype: chained methods that append types to a query (`.anyOf(…)`) do not
     type-check once the query holds two or more types, and operator-built queries
     (`.with(A.self) || .with(B.self)`) nest the row by the shape of the expression and lose it
     behind `some`; terms in one pack avoid both.

2. **Systems declared by their parameters.** A system's `run` takes either the world or system
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
   - **Parameters.** Each parameter type mirrors a value of item 1. `Query<…>` reads its terms
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
