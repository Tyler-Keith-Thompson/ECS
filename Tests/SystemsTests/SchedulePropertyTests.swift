// Random constraint sets checked against what an order must satisfy. Self-contained.

import ECSTestSupport
import PropertyBased
import Systems
import Testing
import WorldModule

struct Slot0: System { func run(in world: inout World) {} }
struct Slot1: System { func run(in world: inout World) {} }
struct Slot2: System { func run(in world: inout World) {} }
struct Slot3: System { func run(in world: inout World) {} }
struct Slot4: System { func run(in world: inout World) {} }

@Suite("Schedule: properties")
struct SchedulePropertyTests {
    @Test("Every acyclic constraint set gives an order satisfying each constraint; a cyclic one throws", .tags(.randomized))
    func ordersSatisfyConstraints() async {
        // Each pair (a, b) with a != b reads "system a runs after system b".
        let edges = Gen.int(in: 0 ... 4).array(of: 2 ... 2).array(of: 0 ... 8)
        await propertyCheck(count: 500, input: edges) { edges in
            let pairs = edges.filter { $0[0] != $0[1] }.map { ($0[0], $0[1]) }
            func system(_ slot: Int) -> ScheduledSystem {
                let base: ScheduledSystem = switch slot {
                case 0: ScheduledSystem(Slot0())
                case 1: ScheduledSystem(Slot1())
                case 2: ScheduledSystem(Slot2())
                case 3: ScheduledSystem(Slot3())
                default: ScheduledSystem(Slot4())
                }
                return pairs.filter { $0.0 == slot }.reduce(base) { system, pair in
                    switch pair.1 {
                    case 0: system.after(Slot0.self)
                    case 1: system.after(Slot1.self)
                    case 2: system.after(Slot2.self)
                    case 3: system.after(Slot3.self)
                    default: system.after(Slot4.self)
                    }
                }
            }
            let systems = (0 ..< 5).map(system)
            let isAcyclic = Self.isAcyclic(pairs)
            do {
                let schedule = try Schedule(checked: systems)
                #expect(isAcyclic)
                let positions = Dictionary(uniqueKeysWithValues: schedule.names.enumerated().map { ($1, $0) })
                #expect(positions.count == 5)
                for (later, earlier) in pairs {
                    #expect(positions["Slot\(later)"]! > positions["Slot\(earlier)"]!)
                }
            } catch {
                #expect(!isAcyclic)
            }
        }
    }

    /// Whether repeatedly removing a node with no remaining "runs after" edge empties the graph.
    static func isAcyclic(_ pairs: [(Int, Int)]) -> Bool {
        var remaining = Set(0 ..< 5)
        while let free = remaining.sorted().first(where: { node in
            !pairs.contains { $0.0 == node && remaining.contains($0.1) }
        }) {
            remaining.remove(free)
        }
        return remaining.isEmpty
    }
}
