import AdjacencyListModule
import GraphFormats
import GraphOperations
import GraphProtocols
import Synchronization
import WorldModule

/// The times one system of a schedule has taken to run.
///
/// Read the timings from a world's ``SystemProfile``.
@frozen
public struct SystemTiming: Hashable, Sendable {
    /// The name of the system's type.
    public let name: String
    /// The number of times the system has run.
    public internal(set) var runs: Int
    /// The total time the system's runs have taken.
    public internal(set) var total: Duration
    /// The time the system's longest run took.
    public internal(set) var longest: Duration
    /// The time the system's latest run took.
    public internal(set) var latest: Duration

    @usableFromInline
    init(name: String) {
        self.name = name
        runs = 0
        total = .zero
        longest = .zero
        latest = .zero
    }

    /// The average time the system's runs have taken, or zero if it hasn't run.
    @inlinable
    public var average: Duration { runs == 0 ? .zero : total / runs }

    mutating func record(_ duration: Duration) {
        runs += 1
        total += duration
        longest = max(longest, duration)
        latest = duration
    }
}

/// A resource that records how long each system takes to run.
///
/// Insert a profile into a world to find out where a schedule spends its time. Every schedule
/// that runs on the world then records each system's runs in it:
///
/// ```swift
/// var world = World()
/// world.resources.insert(SystemProfile())
/// world.spawn(Position(x: 0, y: 100), Velocity(dx: 0, dy: 0))
///
/// let frame = Schedule {
///     Gravity()
///     Movement().after(Gravity.self)
/// }
/// frame.run(on: &world)
/// frame.run(on: &world)
///
/// let timings = world.resources[SystemProfile.self].timings
/// print(timings.map(\.name))
/// // Prints "["Gravity", "Movement"]"
/// print(timings.map(\.runs))
/// // Prints "[2, 2]"
/// ```
///
/// Each ``SystemTiming`` also holds the total, average, longest and latest time of the system's
/// runs.
///
/// A run's time covers the system's own work, measured on a continuous clock: not its
/// conditions, nor the commands it queued, which apply after its wave. A system its conditions
/// skip doesn't run, so nothing is recorded for it. Systems in the same wave run at the same
/// time, so their times can add up to more than the wave took. Insert a new profile to start
/// over.
public struct SystemProfile: Resource {
    /// The timing of each system that has run, in the order the systems first ran.
    public private(set) var timings: [SystemTiming] = []
    var positions: [UInt64: Int] = [:]

    /// Creates an empty profile.
    public init() {}

    mutating func record(_ duration: Duration, for system: ScheduledSystem) {
        let position: Int
        if let existing = positions[system.id] {
            position = existing
        } else {
            position = timings.count
            positions[system.id] = position
            timings.append(SystemTiming(name: system.name))
        }
        timings[position].record(duration)
    }
}

/// The times systems running at once took, gathered from their threads.
final class WaveTimes: Sendable {
    let durations: Mutex<[UInt64: Duration]> = Mutex([:])

    func record(_ duration: Duration, for id: UInt64) {
        durations.withLock { $0[id] = duration }
    }
}

extension Schedule {
    /// Writes the schedule's dependency graph in the DOT language, for drawing with Graphviz.
    ///
    /// Use this method to see why systems run in the order they do, and which could run at the
    /// same time. Each system is a node labeled with its type's name, numbered in the order the
    /// schedule runs them. An arc from one system to another means the second runs after the
    /// first: solid when an ordering constraint orders them, dashed when only their accesses
    /// conflict. Arcs that other arcs imply are left out.
    ///
    /// ```swift
    /// let frame = Schedule {
    ///     Gravity()
    ///     Movement().after(Gravity.self)
    ///     Scoring()
    /// }
    /// var dot = ""
    /// frame.writeDOT(to: &dot)
    ///
    /// let lines = dot.split(separator: "\n").map { line in line.drop { $0 == "\t" } }
    /// print(lines)
    /// // Prints "["digraph {", "0 [label=Gravity];", "1 [label=Movement];", "2 [label=Scoring];", "0 -> 1;", "1 -> 2 [style=dashed];", "}"]"
    /// ```
    ///
    /// Laid out, the DOT text shows that `Movement` is ordered after `Gravity`, and that
    /// `Scoring` runs after `Movement` only because it reads the `Position` that `Movement`
    /// writes:
    ///
    /// ```dot
    /// digraph {
    ///     0 [label=Gravity];
    ///     1 [label=Movement];
    ///     2 [label=Scoring];
    ///     0 -> 1;
    ///     1 -> 2 [style=dashed];
    /// }
    /// ```
    ///
    /// - Parameter output: The stream to write the DOT text to.
    /// - Complexity: O(*s*²) for *s* systems.
    public func writeDOT(to output: inout some TextOutputStream) {
        var dependencies: [DirectedEdge<Int>] = []
        for later in systems.indices {
            for earlier in 0 ..< later where Self.dependsOn(systems[later], systems[earlier]) {
                dependencies.append(DirectedEdge(from: earlier, to: later))
            }
        }
        let graph = AdjacencyList<Int>(vertices: systems.indices, edges: dependencies)
        let reduced = AdjacencyList<Int>.transitiveReduction(of: graph)
        let systems = systems
        do {
            try reduced.writeDOT(
                to: &output,
                vertexAttributes: { [(key: "label", value: .string(systems[$0].name))] },
                edgeAttributes: { index in
                    let edge = reduced.edges[index]
                    return Self.isConstrained(systems[edge.target], after: systems[edge.source]) ? [] : [(key: "style", value: .string("dashed"))]
                }
            )
        } catch {
            preconditionFailure("Systems are numbered uniquely: \(error)")
        }
    }
}
