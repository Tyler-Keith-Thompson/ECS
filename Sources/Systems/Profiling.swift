import AdjacencyListModule
import GraphFormats
import GraphOperations
import GraphProtocols
import Synchronization
import WorldModule

/// How long one system of a schedule took over its runs.
@frozen
public struct SystemTiming: Hashable, Sendable {
    /// The name of the system's type.
    public let name: String
    /// The number of times the system ran.
    public internal(set) var runs: Int
    /// The time its runs took together.
    public internal(set) var total: Duration
    /// The time its longest run took.
    public internal(set) var longest: Duration
    /// The time its latest run took.
    public internal(set) var latest: Duration

    @usableFromInline
    init(name: String) {
        self.name = name
        runs = 0
        total = .zero
        longest = .zero
        latest = .zero
    }

    /// The time its runs took on average.
    @inlinable
    public var average: Duration { runs == 0 ? .zero : total / runs }

    mutating func record(_ duration: Duration) {
        runs += 1
        total += duration
        longest = max(longest, duration)
        latest = duration
    }
}

/// The time each system takes, recorded by every schedule that runs on a world holding this
/// resource.
///
/// ```swift
/// world.resources.insert(SystemProfile())
/// frame.run(on: &world)
/// for timing in world.resources[SystemProfile.self].timings {
///     print(timing.name, timing.average)
/// }
/// ```
///
/// A run measures the system's own body on a continuous clock: not its conditions, nor the
/// commands it queued, which apply after its wave. A system skipped by its conditions does not
/// run. Systems sharing a wave run at the same time, so their times can add up to more than the
/// wave took. Insert a new profile to start over.
public struct SystemProfile: Resource {
    /// Each system that has run, in the order each first ran.
    public private(set) var timings: [SystemTiming] = []
    var positions: [UInt64: Int] = [:]

    /// An empty profile.
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
    /// Writes the schedule's dependency graph as DOT, for Graphviz.
    ///
    /// Each system is a node labeled with its name, in the order the schedule runs them. An arc
    /// from one system to another means the second runs after the first: solid when an `after`
    /// or `before` constraint orders them, dashed when only their accesses conflict. Arcs that
    /// other arcs imply are left out.
    ///
    /// ```swift
    /// var dot = ""
    /// frame.writeDOT(to: &dot)
    /// // digraph {
    /// //     0 [label=Input];
    /// //     1 [label=Movement];
    /// //     0 -> 1;
    /// // }
    /// ```
    ///
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
