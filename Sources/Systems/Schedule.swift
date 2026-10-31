import Traversal
import WorldModule

/// The error ``Schedule/init(checked:)`` throws when the ordering constraints of its systems form
/// a cycle, so no order satisfies them all.
@frozen
public struct CyclicOrdering: Error, Hashable, Sendable {
    @inlinable
    public init() {}
}

/// Builds the systems of a ``Schedule`` from the systems, scheduled systems and schedules written
/// in a block.
@resultBuilder
public enum ScheduleBuilder {
    public static func buildExpression(_ system: some System) -> [ScheduledSystem] { [ScheduledSystem(system)] }
    public static func buildExpression(_ system: some MainActorSystem) -> [ScheduledSystem] { [ScheduledSystem(system)] }
    public static func buildExpression(_ system: ScheduledSystem) -> [ScheduledSystem] { [system] }
    public static func buildExpression(_ schedule: Schedule) -> [ScheduledSystem] { schedule.systems }
    public static func buildBlock(_ parts: [ScheduledSystem]...) -> [ScheduledSystem] { parts.flatMap(\.self) }
    public static func buildOptional(_ part: [ScheduledSystem]?) -> [ScheduledSystem] { part ?? [] }
    public static func buildEither(first part: [ScheduledSystem]) -> [ScheduledSystem] { part }
    public static func buildEither(second part: [ScheduledSystem]) -> [ScheduledSystem] { part }
    public static func buildArray(_ parts: [[ScheduledSystem]]) -> [ScheduledSystem] { parts.flatMap(\.self) }
}

/// Systems that run on a world, as though in the order written, at the same time where they can.
///
/// Systems take the order they are written in, except where `after` and `before` constraints
/// require otherwise: a system that must run before one written earlier is moved up to run just
/// before it. A constraint naming a type with no system in the schedule is ignored, and one
/// naming the system's own type does not order the system against itself.
///
/// Systems that conflict, one writing what the other reads or writes, run in that order; those
/// that do not run at the same time (see ``run(on:)``).
///
/// ```swift
/// let tick = Schedule {
///     Collisions().after(Movement.self)
///     Movement()
///     if debugging { DrawBoxes() }
/// }
/// tick.run(on: &world)  // Movement, Collisions, then DrawBoxes when debugging
/// ```
public struct Schedule: Sendable {
    /// The systems, in an order that satisfies their constraints and in which conflicting
    /// systems run.
    public let systems: [ScheduledSystem]
    /// The positions in ``systems`` of the systems each wave runs at the same time.
    package let waves: [[Int]]

    /// The systems written in `build`, in an order that satisfies their constraints.
    ///
    /// - Complexity: O(*s* + *c*·*k*) for *s* systems, *c* constraints and at most *k* systems
    ///   of one type.
    /// - Precondition: The constraints form no cycle. Use ``init(checked:)`` to throw instead.
    public init(@ScheduleBuilder _ build: () -> [ScheduledSystem]) {
        guard let systems = Self.ordered(build()) else {
            preconditionFailure("The schedule's ordering constraints form a cycle")
        }
        self.init(ordered: systems)
    }

    /// `systems`, in an order that satisfies their constraints.
    ///
    /// ```swift
    /// let tick = try Schedule(checked: [Collisions().after(Movement.self), ScheduledSystem(Movement())])
    /// ```
    ///
    /// - Complexity: O(*s* + *c*·*k*) for *s* systems, *c* constraints and at most *k* systems
    ///   of one type.
    /// - Throws: ``CyclicOrdering`` when the constraints form a cycle.
    public init(checked systems: [ScheduledSystem]) throws(CyclicOrdering) {
        guard let ordered = Self.ordered(systems) else { throw CyclicOrdering() }
        self.init(ordered: ordered)
    }

    /// This schedule, each of its systems run only when `condition` holds for the world at the
    /// start of the wave that system runs in.
    ///
    /// The condition is checked once per system, so a system in an earlier wave that changes what
    /// it depends on stops the systems after it.
    ///
    /// ```swift
    /// let frame = Schedule {
    ///     Input()
    ///     Schedule {
    ///         Movement()
    ///         Collisions()
    ///     }
    ///     .runIf { world in !world.resources.contains(Paused.self) }
    /// }
    /// ```
    ///
    /// - Complexity: O(*s*) for *s* systems.
    public func runIf(_ condition: @escaping @Sendable (World) -> Bool) -> Schedule {
        Schedule(ordered: systems.map { $0.runIf(condition) })
    }

    /// This schedule, each of its systems also ordered after every system of each of `sets`.
    ///
    /// - Precondition: The constraints form no cycle.
    public func after<each S: SystemSet>(_ sets: repeat (each S).Type) -> Schedule {
        Schedule { for system in systems { system.after(repeat each sets) } }
    }

    /// This schedule, each of its systems also ordered before every system of each of `sets`.
    ///
    /// - Precondition: The constraints form no cycle.
    public func before<each S: SystemSet>(_ sets: repeat (each S).Type) -> Schedule {
        Schedule { for system in systems { system.before(repeat each sets) } }
    }

    /// This schedule, each of its systems also in each of `sets`.
    ///
    /// - Precondition: The constraints form no cycle.
    public func inSet<each S: SystemSet>(_ sets: repeat (each S).Type) -> Schedule {
        Schedule { for system in systems { system.inSet(repeat each sets) } }
    }

    /// This schedule, each of its systems also free to run in either order with every system of
    /// each of `sets`.
    public func ambiguous<each S: SystemSet>(with sets: repeat (each S).Type) -> Schedule {
        Schedule(ordered: systems.map { $0.ambiguous(with: repeat each sets) })
    }

    /// `systems`, already in an order that satisfies their constraints.
    init(ordered systems: [ScheduledSystem]) {
        self.systems = systems
        waves = Self.waves(of: systems)
    }

    /// The names of the systems, in the order of ``systems``.
    public var names: [String] { systems.map(\.name) }

    /// Runs every system once on `world`, running systems that do not depend on each other at the
    /// same time.
    ///
    /// A system depends on the systems before it that it must run after, by an `after` or
    /// `before` constraint, and on those it conflicts with: one writes what the other reads or
    /// writes, or either has no ``System/access``. The systems run in waves: each wave holds the
    /// systems whose dependencies all ran in earlier waves, and runs them with
    /// ``WorldModule/World/runConcurrently(_:)``. A system without an access runs alone. The world
    /// ends as it would running the systems one after another in order.
    ///
    /// At the start of each wave, every condition of its systems is checked, so a condition reads
    /// only what its system's access lists, and the world's change tick advances. Each system's
    /// ``WorldModule/World/lastRun`` is the tick of its previous run, so filters such as
    /// `.changed(Position.self)` show it what changed since then: changes made by the systems
    /// after it on the previous run and before it on this one, but not its own. A system that has
    /// not run on this world before sees every component as added and changed. A skipped system
    /// has not run: the next time it runs, it sees everything since it last did.
    ///
    /// Before the first wave, each system that has not run on this world is initialized
    /// (``System/initialize(in:)``).
    ///
    /// Command buffers the wave's systems queue (``WorldModule/World/queue(_:)``) apply at the end
    /// of the wave, in the order the systems run. The tick advances once more after the last wave,
    /// so changes made to the world between runs are newer than every system's previous run.
    ///
    /// A ``MainActorSystem`` runs on the calling thread after the other systems of its wave.
    ///
    /// - Precondition: Every system with an access reads and writes only what it lists; see
    ///   ``WorldModule/World/runConcurrently(_:)``. A schedule whose main-actor systems run is run
    ///   on the main actor.
    public func run(on world: inout World) {
        run(on: &world, concurrently: true)
    }

    /// Runs every system once on `world`, as ``run(on:)`` does but one system at a time.
    ///
    /// The waves, conditions, change ticks and commands are those of ``run(on:)``, so the two
    /// end with the same world; running serially makes a system's work easy to step through.
    public func runSerially(on world: inout World) {
        run(on: &world, concurrently: false)
    }

    func run(on world: inout World, concurrently: Bool) {
        let outerLastRun = world.lastRun
        defer {
            world.lastRun = outerLastRun
            world.advanceChangeTick()
        }
        let previousRuns = world.resources.contains(SystemRuns.self) ? world.resources[SystemRuns.self].ticks : [:]
        for system in systems where previousRuns[system.id] == nil {
            system.initialize(in: &world)
        }
        for wave in waves {
            let group = wave.map { systems[$0] }.filter { $0.shouldRun(in: world) }
            guard !group.isEmpty else { continue }
            let runs = world.resources.contains(SystemRuns.self) ? world.resources[SystemRuns.self].ticks : [:]
            let tick = world.advanceChangeTick()
            let concurrent = group.filter { !$0.runsOnMainActor }
            let profiling = world.resources.contains(SystemProfile.self)
            if concurrent.count <= 1 || !concurrently {
                for system in group {
                    world.lastRun = runs[system.id] ?? .zero
                    Self.run(system, on: &world, profiling: profiling)
                }
            } else {
                let times = WaveTimes()
                world.runConcurrently(concurrent.map { system in
                    let lastRun = runs[system.id] ?? .zero
                    return ConcurrentChange(access: system.access!) { world in
                        world.lastRun = lastRun
                        if profiling {
                            times.record(ContinuousClock().measure { system.run(in: &world) }, for: system.id)
                        } else {
                            system.run(in: &world)
                        }
                    }
                })
                if profiling, world.resources.contains(SystemProfile.self) {
                    let durations = times.durations.withLock { $0 }
                    for system in concurrent {
                        world.resources[SystemProfile.self].record(durations[system.id] ?? .zero, for: system)
                    }
                }
                for system in group where system.runsOnMainActor {
                    world.lastRun = runs[system.id] ?? .zero
                    Self.run(system, on: &world, profiling: profiling)
                }
            }
            world.applyQueuedCommands()
            var updated = world.resources.contains(SystemRuns.self) ? world.resources[SystemRuns.self] : SystemRuns(ticks: [:])
            for system in group {
                updated.ticks[system.id] = tick
            }
            world.resources.insert(updated)
        }
    }

    /// Runs `system` on `world`, recording its time in the world's ``SystemProfile`` when
    /// `profiling`.
    static func run(_ system: ScheduledSystem, on world: inout World, profiling: Bool) {
        guard profiling else {
            system.run(in: &world)
            return
        }
        let duration = ContinuousClock().measure { system.run(in: &world) }
        guard world.resources.contains(SystemProfile.self) else { return }
        world.resources[SystemProfile.self].record(duration, for: system)
    }

    /// The positions in `systems` of each wave's systems, waves in the order they run.
    ///
    /// A longest-path layering of the dependency graph: `systems` is already in an order every
    /// dependency follows, so one pass puts each system one wave after the latest of its
    /// dependencies.
    ///
    /// - Complexity: O(*s*²) for *s* systems.
    static func waves(of systems: [ScheduledSystem]) -> [[Int]] {
        var waveOf = [Int](repeating: 0, count: systems.count)
        var waves: [[Int]] = []
        for later in systems.indices {
            var wave = 0
            for earlier in 0 ..< later where waveOf[earlier] >= wave
                && dependsOn(systems[later], systems[earlier]) {
                wave = waveOf[earlier] + 1
            }
            waveOf[later] = wave
            if wave == waves.count { waves.append([]) }
            waves[wave].append(later)
        }
        return waves
    }

    /// Whether an `after` or `before` constraint orders `later` after `earlier`.
    static func isConstrained(_ later: ScheduledSystem, after earlier: ScheduledSystem) -> Bool {
        let earlierLabels = earlier.labels
        let laterLabels = later.labels
        return later.predecessors.contains(where: earlierLabels.contains)
            || earlier.successors.contains(where: laterLabels.contains)
    }

    /// Whether `later` must run after `earlier`, which comes before it in the schedule: a
    /// constraint orders them, or they conflict.
    static func dependsOn(_ later: ScheduledSystem, _ earlier: ScheduledSystem) -> Bool {
        if isConstrained(later, after: earlier) {
            return true
        }
        guard let laterAccess = later.access, let earlierAccess = earlier.access else { return true }
        return laterAccess.conflicts(with: earlierAccess)
    }

    /// `systems` reordered to satisfy their constraints, or nil if the constraints form a cycle.
    ///
    /// A depth-first postorder over "must run after" edges, from each system in written order:
    /// every system follows the systems it must run after, and otherwise keeps its written place.
    static func ordered(_ systems: [ScheduledSystem]) -> [ScheduledSystem]? {
        var positionsByType: [ObjectIdentifier: [Int]] = [:]
        for (position, system) in systems.enumerated() {
            for label in system.labels {
                positionsByType[label, default: []].append(position)
            }
        }
        var predecessors = [[Int]](repeating: [], count: systems.count)
        for (position, system) in systems.enumerated() {
            for type in system.predecessors {
                predecessors[position] += positionsByType[type, default: []].filter { $0 != position }
            }
            for type in system.successors {
                for successor in positionsByType[type, default: []] where successor != position {
                    predecessors[successor].append(position)
                }
            }
        }
        for position in predecessors.indices {
            predecessors[position].sort()
        }
        // topologicalSort follows edges forward and returns the reverse postorder, so over
        // "must run after" edges its reverse is an order in which every system follows those it
        // must run after.
        guard let order = topologicalSort(from: systems.indices, successors: { predecessors[$0] }) else {
            return nil
        }
        return order.reversed().map { systems[$0] }
    }
}

/// Two systems of a schedule whose accesses conflict but which no `after` or `before`
/// constraint orders, directly or through other systems, so the order they run in rests on the
/// order they were written in.
@frozen
public struct Ambiguity: Hashable, Sendable {
    /// The position in ``Schedule/systems`` of the system that runs first.
    public let first: Int
    /// The position in ``Schedule/systems`` of the system that runs second.
    public let second: Int

    @inlinable
    public init(first: Int, second: Int) {
        self.first = first
        self.second = second
    }
}

extension Schedule {
    /// Every pair of systems whose accesses conflict but which no constraint orders, in the
    /// order of ``systems``.
    ///
    /// Such a pair runs in the order written, which is easy to change by accident. Order each
    /// pair with `after` or `before`, or mark it with
    /// ``ScheduledSystem/ambiguous(with:)`` when either order is right. Systems without an access
    /// run alone, in the order written, and are left out.
    ///
    /// ```swift
    /// #expect(frame.ambiguities().isEmpty)
    /// ```
    ///
    /// - Complexity: O(*s*·(*s* + *c*)) for *s* systems and *c* ordered pairs.
    public func ambiguities() -> [Ambiguity] {
        var successors = [[Int]](repeating: [], count: systems.count)
        for later in systems.indices {
            for earlier in 0 ..< later where Self.isConstrained(systems[later], after: systems[earlier]) {
                successors[earlier].append(later)
            }
        }
        var ambiguities: [Ambiguity] = []
        for first in systems.indices {
            guard let firstAccess = systems[first].access else { continue }
            var ordered: Set<Int> = []
            for case .discover(let reached) in depthFirstSearch(from: [first], successors: { successors[$0] }) {
                ordered.insert(reached)
            }
            for second in systems.indices where second > first && !ordered.contains(second) {
                guard let secondAccess = systems[second].access, firstAccess.conflicts(with: secondAccess),
                      !systems[first].ambiguousTypes.contains(where: systems[second].labels.contains),
                      !systems[second].ambiguousTypes.contains(where: systems[first].labels.contains)
                else { continue }
                ambiguities.append(Ambiguity(first: first, second: second))
            }
        }
        return ambiguities
    }
}

/// The change tick at which each system last started running on a world, kept in the world so
/// that it is copied, saved and restored with everything else.
struct SystemRuns: Resource {
    var ticks: [UInt64: ChangeTick]
}
