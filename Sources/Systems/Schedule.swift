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
    public static func buildExpression(_ system: ScheduledSystem) -> [ScheduledSystem] { [system] }
    public static func buildExpression(_ schedule: Schedule) -> [ScheduledSystem] { schedule.systems }
    public static func buildBlock(_ parts: [ScheduledSystem]...) -> [ScheduledSystem] { parts.flatMap(\.self) }
    public static func buildOptional(_ part: [ScheduledSystem]?) -> [ScheduledSystem] { part ?? [] }
    public static func buildEither(first part: [ScheduledSystem]) -> [ScheduledSystem] { part }
    public static func buildEither(second part: [ScheduledSystem]) -> [ScheduledSystem] { part }
    public static func buildArray(_ parts: [[ScheduledSystem]]) -> [ScheduledSystem] { parts.flatMap(\.self) }
}

/// Systems in the order they run.
///
/// Systems run in the order they are written, except where `after` and `before` constraints
/// require otherwise: a system that must run before one written earlier is moved up to run just
/// before it.
/// A constraint naming a type with no system in the schedule is ignored, and one naming the
/// system's own type does not order the system against itself.
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
    /// The systems, in the order they run.
    public let systems: [ScheduledSystem]

    /// The systems written in `build`, in an order that satisfies their constraints.
    ///
    /// - Complexity: O(*s* + *c*·*k*) for *s* systems, *c* constraints and at most *k* systems
    ///   of one type.
    /// - Precondition: The constraints form no cycle. Use ``init(checked:)`` to throw instead.
    public init(@ScheduleBuilder _ build: () -> [ScheduledSystem]) {
        guard let systems = Self.ordered(build()) else {
            preconditionFailure("The schedule's ordering constraints form a cycle")
        }
        self.systems = systems
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
        self.systems = ordered
    }

    /// This schedule, each of its systems run only when `condition` holds for the world just
    /// before that system would run.
    ///
    /// The condition is checked once per system, so a system that changes what it depends on
    /// stops the systems after it.
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

    /// `systems`, already in an order that satisfies their constraints.
    init(ordered systems: [ScheduledSystem]) {
        self.systems = systems
    }

    /// The names of the systems, in the order they run.
    public var names: [String] { systems.map(\.name) }

    /// Runs every system once on `world`, in order, skipping those whose conditions do not hold
    /// for the world just before their turn.
    ///
    /// Before each system, the world's change tick advances and its ``WorldModule/World/lastRun``
    /// is set to the tick of that system's previous run, so filters such as
    /// `.changed(Position.self)` show the system what changed since then: changes made by the
    /// systems after it on the previous run and before it on this one, but not its own. A system
    /// that has not run on this world before sees every component as added and changed. A
    /// skipped system has not run: the next time it runs, it sees everything since it last did.
    ///
    /// The tick advances once more after the last system, so changes made to the world between
    /// runs are newer than every system's previous run.
    public func run(on world: inout World) {
        let outerLastRun = world.lastRun
        defer {
            world.lastRun = outerLastRun
            world.advanceChangeTick()
        }
        for system in systems where system.shouldRun(in: world) {
            let hasRuns = world.resources.contains(SystemRuns.self)
            world.lastRun = hasRuns ? world.resources[SystemRuns.self].ticks[system.id] ?? .zero : .zero
            let tick = world.advanceChangeTick()
            system.run(in: &world)
            if world.resources.contains(SystemRuns.self) {
                world.resources[SystemRuns.self].ticks[system.id] = tick
            } else {
                world.resources.insert(SystemRuns(ticks: [system.id: tick]))
            }
        }
    }

    /// `systems` reordered to satisfy their constraints, or nil if the constraints form a cycle.
    ///
    /// A depth-first postorder over "must run after" edges, from each system in written order:
    /// every system follows the systems it must run after, and otherwise keeps its written place.
    static func ordered(_ systems: [ScheduledSystem]) -> [ScheduledSystem]? {
        var positionsByType: [ObjectIdentifier: [Int]] = [:]
        for (position, system) in systems.enumerated() {
            positionsByType[system.type, default: []].append(position)
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

/// The change tick at which each system last started running on a world, kept in the world so
/// that it is copied, saved and restored with everything else.
struct SystemRuns: Resource {
    var ticks: [UInt64: ChangeTick]
}
