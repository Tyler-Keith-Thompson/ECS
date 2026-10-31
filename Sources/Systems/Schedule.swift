import Traversal
import WorldModule

/// An error indicating that the ordering constraints of a schedule's systems form a cycle, so no
/// order satisfies them all.
///
/// ``Schedule/init(checked:)`` throws this error.
@frozen
public struct CyclicOrdering: Error, Hashable, Sendable {
    /// Creates the error.
    @inlinable
    public init() {}
}

/// A result builder that collects the systems written in a ``Schedule``'s closure.
///
/// A schedule's closure can list systems, main-actor systems, scheduled systems (a system with
/// modifiers such as `after(_:)`) and other schedules, whose systems are added in place. It can
/// also use `if`, `if`-`else`, `switch` and `for`-`in`:
///
/// ```swift
/// let world = World()
/// let frame = Schedule {
///     Gravity()
///     Movement().after(Gravity.self)
///     if world.resources.contains(Score.self) {
///         Scoring()
///     }
/// }
/// print(frame.names)
/// // Prints "["Gravity", "Movement"]"
/// ```
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

/// A list of systems that run on a world, in order, and at the same time where they can.
///
/// A schedule holds the systems of one frame or step of a simulation. You build it by listing
/// the systems in a closure, and run it on a world with ``run(on:)``, which runs each system once:
///
/// ```swift
/// var world = World()
/// let ball = world.spawn(Position(x: 0, y: 100), Velocity(dx: 2, dy: 0))
///
/// let frame = Schedule {
///     Gravity()
///     Movement().after(Gravity.self)
/// }
/// frame.run(on: &world)
/// frame.run(on: &world)
/// print(world[Position.self, of: ball])
/// // Prints "Position(x: 4.0, y: 70.0)"
/// ```
///
/// ### Ordering Systems
///
/// Systems run in the order they're written, except where an ordering constraint requires
/// otherwise. A system that must run after one written later, by `after(_:)`, or before one
/// written earlier, by `before(_:)`, is moved to satisfy the constraint, and every other system
/// keeps its written place:
///
/// ```swift
/// let frame = Schedule {
///     Scoring().after(Movement.self)
///     Movement()
///     Gravity().before(Movement.self)
/// }
/// print(frame.names)
/// // Prints "["Gravity", "Movement", "Scoring"]"
/// ```
///
/// A constraint naming a type with no system in the schedule is ignored, and one naming a
/// system's own type doesn't order the system against itself. Constraints that form a cycle,
/// so that no order satisfies them all, trap; build the schedule with ``init(checked:)`` to throw
/// ``CyclicOrdering`` instead.
///
/// ### Running Systems at the Same Time
///
/// Two systems *conflict* when one writes a type the other reads or writes, or when either has no
/// ``System/access``. ``run(on:)`` runs conflicting systems in order and the rest at the same
/// time, and the world ends as though the systems had run one after another in order.
///
/// When two conflicting systems aren't ordered by any constraint, the order they run in rests
/// only on how they happen to be written. ``ambiguities()`` lists those pairs, so a test can
/// keep a schedule free of them.
public struct Schedule: Sendable {
    /// The schedule's systems, in the order they run.
    ///
    /// The order satisfies every ordering constraint, and conflicting systems run in this order.
    public let systems: [ScheduledSystem]
    /// The positions in ``systems`` of the systems each wave runs at the same time.
    package let waves: [[Int]]

    /// Creates a schedule of the systems listed in a closure.
    ///
    /// - Parameter build: A closure listing the systems; see ``ScheduleBuilder``.
    /// - Complexity: O(*s* + *c*·*k*) for *s* systems, *c* constraints and at most *k* systems
    ///   of one type.
    /// - Precondition: The ordering constraints form no cycle. The checked initializer,
    ///   ``init(checked:)``, throws instead.
    public init(@ScheduleBuilder _ build: () -> [ScheduledSystem]) {
        guard let systems = Self.ordered(build()) else {
            preconditionFailure("The schedule's ordering constraints form a cycle")
        }
        self.init(ordered: systems)
    }

    /// Creates a schedule of the given systems, throwing an error if their ordering constraints
    /// form a cycle.
    ///
    /// Use this initializer when the systems or their constraints come from elsewhere, such as
    /// from configuration, and a cycle is an error to report rather than a bug:
    ///
    /// ```swift
    /// do {
    ///     _ = try Schedule(checked: [
    ///         Movement().after(Gravity.self),
    ///         Gravity().after(Movement.self),
    ///     ])
    /// } catch {
    ///     print(error)
    ///     // Prints "CyclicOrdering()"
    /// }
    /// ```
    ///
    /// - Parameter systems: The systems, in the order to run them where constraints allow.
    /// - Complexity: O(*s* + *c*·*k*) for *s* systems, *c* constraints and at most *k* systems
    ///   of one type.
    /// - Throws: ``CyclicOrdering`` when the constraints form a cycle.
    public init(checked systems: [ScheduledSystem]) throws(CyclicOrdering) {
        guard let ordered = Self.ordered(systems) else { throw CyclicOrdering() }
        self.init(ordered: ordered)
    }

    /// Returns this schedule with each of its systems run only when a condition holds.
    ///
    /// Use this method to switch a group of systems on and off together. The following example
    /// stops physics while the world holds a `Paused` resource, but keeps scoring:
    ///
    /// ```swift
    /// var world = World()
    /// world.resources.insert(Score(points: 0))
    /// world.resources.insert(Paused())
    /// let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    ///
    /// let frame = Schedule {
    ///     Schedule {
    ///         Gravity()
    ///         Movement().after(Gravity.self)
    ///     }
    ///     .runIf { world in !world.resources.contains(Paused.self) }
    ///     Scoring().after(Movement.self)
    /// }
    /// frame.run(on: &world)
    /// print(world[Position.self, of: ball].x)
    /// // Prints "0.0"
    /// print(world.resources[Score.self].points)
    /// // Prints "1"
    /// ```
    ///
    /// The condition is checked separately for each system, at the start of the wave it runs in,
    /// so a system that changes what the condition reads stops the systems in later waves.
    ///
    /// - Parameter condition: A closure that takes the world and returns whether a system runs.
    ///   It must read only what each system's access lists.
    /// - Returns: A schedule whose systems each have the condition added.
    /// - Complexity: O(*s*) for *s* systems.
    public func runIf(_ condition: @escaping @Sendable (World) -> Bool) -> Schedule {
        Schedule(ordered: systems.map { $0.runIf(condition) })
    }

    /// Returns this schedule with each of its systems ordered to run after every system in each
    /// of the given sets.
    ///
    /// - Parameter sets: The system types and system sets to run after.
    /// - Returns: A schedule whose systems each have the ordering constraint added.
    /// - Precondition: The constraints form no cycle.
    public func after<each S: SystemSet>(_ sets: repeat (each S).Type) -> Schedule {
        Schedule { for system in systems { system.after(repeat each sets) } }
    }

    /// Returns this schedule with each of its systems ordered to run before every system in each
    /// of the given sets.
    ///
    /// - Parameter sets: The system types and system sets to run before.
    /// - Returns: A schedule whose systems each have the ordering constraint added.
    /// - Precondition: The constraints form no cycle.
    public func before<each S: SystemSet>(_ sets: repeat (each S).Type) -> Schedule {
        Schedule { for system in systems { system.before(repeat each sets) } }
    }

    /// Returns this schedule with each of its systems a member of each of the given system sets.
    ///
    /// See ``SystemSet``.
    ///
    /// - Parameter sets: The system sets to join.
    /// - Returns: A schedule whose systems are each in the given sets.
    /// - Precondition: The constraints form no cycle.
    public func inSet<each S: SystemSet>(_ sets: repeat (each S).Type) -> Schedule {
        Schedule { for system in systems { system.inSet(repeat each sets) } }
    }

    /// Returns this schedule with each of its systems free to run in either order with every
    /// system in each of the given sets.
    ///
    /// See ``ScheduledSystem/ambiguous(with:)``.
    ///
    /// - Parameter sets: The system types and system sets either order is right with.
    /// - Returns: A schedule whose systems ``ambiguities()`` doesn't report with those sets.
    public func ambiguous<each S: SystemSet>(with sets: repeat (each S).Type) -> Schedule {
        Schedule(ordered: systems.map { $0.ambiguous(with: repeat each sets) })
    }

    /// `systems`, already in an order that satisfies their constraints.
    init(ordered systems: [ScheduledSystem]) {
        self.systems = systems
        waves = Self.waves(of: systems)
    }

    /// The names of the schedule's systems' types, in the order the systems run.
    public var names: [String] { systems.map(\.name) }

    /// Runs each system once on a world, running systems that don't depend on each other at the
    /// same time.
    ///
    /// The world ends as though the systems had run one after another, in the order of
    /// ``systems``.
    ///
    /// A system depends on the systems before it that a constraint orders it after, and on those
    /// it conflicts with: one writes what the other reads or writes, or either has no
    /// ``System/access``. The systems run in *waves*. Each wave holds the systems whose
    /// dependencies all ran in earlier waves, and runs them at the same time with
    /// ``/WorldModule/World/runConcurrently(_:)``. A system without an access runs alone, and a
    /// ``MainActorSystem`` runs on the calling thread after the other systems of its wave.
    ///
    /// Before the first wave, each system that hasn't run on this world before is initialized
    /// (``System/initialize(in:)``). At the start of each wave, the conditions of its systems are
    /// checked, and systems whose conditions don't hold are skipped. Commands the wave's systems
    /// queue apply at the end of the wave, in the order the systems run.
    ///
    /// ### Change Detection
    ///
    /// The world's change tick advances at the start of each wave. While a system runs, the
    /// world's ``/WorldModule/World/lastRun`` is the tick of that system's previous run, so a
    /// filter such as `Changed<Position>` shows it what changed since then: the changes the
    /// systems after it made on the previous run and the systems before it made on this one, but
    /// not its own. The following system counts the positions that changed since it last ran:
    ///
    /// ```swift
    /// struct Moves: Resource { var count: Int }
    ///
    /// @System
    /// struct CountMoves {
    ///     func run(_ moved: Query<Position>.Where<Changed<Position>>, _ moves: ResourceWriter<Moves>) {
    ///         for _ in moved { moves.value.count += 1 }
    ///     }
    /// }
    ///
    /// var world = World()
    /// world.resources.insert(Moves(count: 0))
    /// let ball = world.spawn(Position(x: 0, y: 0))
    /// world.spawn(Position(x: 5, y: 0))
    ///
    /// let frame = Schedule { CountMoves() }
    /// frame.run(on: &world)
    /// print(world.resources[Moves.self].count)
    /// // Prints "2"
    ///
    /// world[Position.self, of: ball].x = 1
    /// frame.run(on: &world)
    /// print(world.resources[Moves.self].count)
    /// // Prints "3"
    /// ```
    ///
    /// A system that hasn't run on this world before sees every component as added and changed.
    /// A skipped system hasn't run, so the next time it runs it sees every change since it last
    /// did. The tick advances once more after the last wave, so changes you make to the world
    /// between runs are newer than every system's previous run.
    ///
    /// - Parameter world: The world to run the systems on.
    /// - Precondition: Every system with an access reads and writes only what it lists; see
    ///   ``/WorldModule/World/runConcurrently(_:)``. A schedule holding a main-actor system that
    ///   runs is run on the main actor.
    public func run(on world: inout World) {
        run(on: &world, concurrently: true)
    }

    /// Runs each system once on a world, one system at a time.
    ///
    /// This method runs the same waves as ``run(on:)``, with the same conditions, change ticks
    /// and commands, so the two end with the same world. Use it when you want to step through a
    /// system's work in a debugger, or to rule out running at the same time as the cause of a
    /// problem.
    ///
    /// - Parameter world: The world to run the systems on.
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
    /// `profiling`; in debug builds, a system with an access traps on reaching anything else.
    static func run(_ system: ScheduledSystem, on world: inout World, profiling: Bool) {
        world.restrictAccess(to: system.access)
        defer { world.restrictAccess(to: nil) }
        guard profiling else {
            system.run(in: &world)
            return
        }
        let duration = ContinuousClock().measure { system.run(in: &world) }
        world.restrictAccess(to: nil)
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

/// Two systems of a schedule whose accesses conflict but that no ordering constraint orders, so
/// the order they run in rests only on the order they were written in.
///
/// ``Schedule/ambiguities()`` returns the ambiguities of a schedule.
@frozen
public struct Ambiguity: Hashable, Sendable {
    /// The position in ``Schedule/systems`` of the system that runs first.
    public let first: Int
    /// The position in ``Schedule/systems`` of the system that runs second.
    public let second: Int

    /// Creates an ambiguity between the systems at two positions of a schedule.
    ///
    /// - Parameters:
    ///   - first: The position of the system that runs first.
    ///   - second: The position of the system that runs second.
    @inlinable
    public init(first: Int, second: Int) {
        self.first = first
        self.second = second
    }
}

extension Schedule {
    /// Returns every pair of systems whose accesses conflict but that no ordering constraint
    /// orders.
    ///
    /// Such a pair runs in the order it's written in, which is easy to change by accident. In the
    /// following schedule, `Gravity` writes the `Velocity` that `Movement` reads, but nothing
    /// says which runs first:
    ///
    /// ```swift
    /// let frame = Schedule {
    ///     Gravity()
    ///     Movement()
    /// }
    /// for ambiguity in frame.ambiguities() {
    ///     print(frame.names[ambiguity.first], frame.names[ambiguity.second])
    ///     // Prints "Gravity Movement"
    /// }
    ///
    /// let ordered = Schedule {
    ///     Gravity()
    ///     Movement().after(Gravity.self)
    /// }
    /// print(ordered.ambiguities().isEmpty)
    /// // Prints "true"
    /// ```
    ///
    /// Order each pair with `after(_:)` or `before(_:)`, or mark it with
    /// ``ScheduledSystem/ambiguous(with:)`` when either order is right. Systems without an access
    /// always run alone, in the order written, and are left out. Call this method in a test to
    /// keep a schedule free of ambiguities.
    ///
    /// - Returns: The ambiguous pairs, ordered by the position of their first system and then
    ///   their second.
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
