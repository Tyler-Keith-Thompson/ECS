// Pairs of conflicting systems no constraint orders. Self-contained: the systems are below.

import ECSTestSupport
import PropertyBased
import Systems
import Testing
import WorldModule

struct GravityWriter: System {
    var access: Access? { .writes(Velocity.self) }
    func run(in world: inout World) {}
}

struct DragWriter: System {
    var access: Access? { .writes(Velocity.self) }
    func run(in world: inout World) {}
}

struct VelocityReader: System {
    var access: Access? { .reads(Velocity.self) }
    func run(in world: inout World) {}
}

struct HealthWriter: System {
    var access: Access? { .writes(Health.self) }
    func run(in world: inout World) {}
}

struct AnythingGoes: System {
    func run(in world: inout World) {}
}

/// A system whose access and type identity come from its slot, for randomized schedules.
struct Slotted<Tag>: System {
    let access: Access?
    func run(in world: inout World) {}
}

enum Tag0 {}
enum Tag1 {}
enum Tag2 {}
enum Tag3 {}
enum Tag4 {}

@Suite("Schedule: ambiguities")
struct AmbiguityTests {
    @Test("An empty schedule and a schedule of one system have none")
    func trivial() {
        #expect(Schedule {}.ambiguities().isEmpty)
        #expect(Schedule { GravityWriter() }.ambiguities().isEmpty)
    }

    @Test("Two writers of one type with no constraint are ambiguous")
    func twoWriters() {
        let schedule = Schedule {
            GravityWriter()
            HealthWriter()
            DragWriter()
        }
        let expected: [Ambiguity] = [Ambiguity(first: 0, second: 2)]
        #expect(schedule.ambiguities() == expected)
    }

    @Test("A writer and a reader of one type are ambiguous; two readers are not")
    func readerAndWriter() {
        let schedule = Schedule {
            VelocityReader()
            VelocityReader()
            GravityWriter()
        }
        let expected: [Ambiguity] = [Ambiguity(first: 0, second: 2), Ambiguity(first: 1, second: 2)]
        #expect(schedule.ambiguities() == expected)
    }

    @Test("A constraint in either direction orders a pair")
    func constrained() {
        let after = Schedule {
            GravityWriter()
            DragWriter().after(GravityWriter.self)
        }
        let before = Schedule {
            GravityWriter().before(DragWriter.self)
            DragWriter()
        }
        #expect(after.ambiguities().isEmpty)
        #expect(before.ambiguities().isEmpty)
    }

    @Test("Constraints through another system order a pair")
    func transitive() {
        let schedule = Schedule {
            GravityWriter()
            AnythingGoes().after(GravityWriter.self)
            DragWriter().after(AnythingGoes.self)
        }
        #expect(schedule.ambiguities().isEmpty)
    }

    @Test("Systems without an access are left out")
    func exclusive() {
        let schedule = Schedule {
            AnythingGoes()
            GravityWriter()
            AnythingGoes()
        }
        #expect(schedule.ambiguities().isEmpty)
    }

    @Test("Marking either system ambiguous with the other's type leaves the pair out")
    func marked() {
        let first = Schedule {
            GravityWriter().ambiguous(with: DragWriter.self)
            DragWriter()
        }
        let second = Schedule {
            GravityWriter()
            DragWriter().ambiguous(with: GravityWriter.self)
        }
        #expect(first.ambiguities().isEmpty)
        #expect(second.ambiguities().isEmpty)
    }

    @Test("Marking a pair leaves the system's other ambiguities")
    func markedOnlyThatPair() {
        let schedule = Schedule {
            GravityWriter().ambiguous(with: DragWriter.self)
            DragWriter()
            VelocityReader()
        }
        let expected: [Ambiguity] = [Ambiguity(first: 0, second: 2), Ambiguity(first: 1, second: 2)]
        #expect(schedule.ambiguities() == expected)
    }

    @Test("Ambiguities are the conflicting pairs the transitive closure of the constraints leaves unordered", .tags(.randomized))
    func matchesClosure() async {
        // Each system: an access code (0: none, 1: reads First, 2: writes First, 3: writes
        // Second) and the slots it runs after.
        let codes = Gen.int(in: 0 ... 3).array(of: 5 ... 5)
        let edges = Gen.int(in: 0 ... 4).array(of: 2 ... 2).array(of: 0 ... 6)
        await propertyCheck(count: 300, input: codes, edges) { codes, edges in
            let pairs = edges.filter { $0[0] != $0[1] }.map { ($0[0], $0[1]) }
            func access(_ code: Int) -> Access? {
                switch code {
                case 1: .reads(First.self)
                case 2: .writes(First.self)
                case 3: .writes(Second.self)
                default: nil
                }
            }
            func system(_ slot: Int) -> ScheduledSystem {
                let base: ScheduledSystem = switch slot {
                case 0: ScheduledSystem(Slotted<Tag0>(access: access(codes[0])))
                case 1: ScheduledSystem(Slotted<Tag1>(access: access(codes[1])))
                case 2: ScheduledSystem(Slotted<Tag2>(access: access(codes[2])))
                case 3: ScheduledSystem(Slotted<Tag3>(access: access(codes[3])))
                default: ScheduledSystem(Slotted<Tag4>(access: access(codes[4])))
                }
                return pairs.filter { $0.0 == slot }.reduce(base) { system, pair in
                    switch pair.1 {
                    case 0: system.after(Slotted<Tag0>.self)
                    case 1: system.after(Slotted<Tag1>.self)
                    case 2: system.after(Slotted<Tag2>.self)
                    case 3: system.after(Slotted<Tag3>.self)
                    default: system.after(Slotted<Tag4>.self)
                    }
                }
            }
            guard let schedule = try? Schedule(checked: (0 ..< 5).map(system)) else { return }
            // Slots by position, and the closure of "runs after" over slots (Floyd–Warshall).
            let slotAt: [Int] = schedule.names.map { name in
                ["Tag0", "Tag1", "Tag2", "Tag3", "Tag4"].firstIndex { name.contains($0) }!
            }
            var after = [[Bool]](repeating: [Bool](repeating: false, count: 5), count: 5)
            for (later, earlier) in pairs { after[later][earlier] = true }
            for middle in 0 ..< 5 {
                for later in 0 ..< 5 {
                    for earlier in 0 ..< 5 where after[later][middle] && after[middle][earlier] {
                        after[later][earlier] = true
                    }
                }
            }
            var expected: [Ambiguity] = []
            for first in 0 ..< 5 {
                for second in first + 1 ..< 5 {
                    let a = slotAt[first]
                    let b = slotAt[second]
                    guard let accessA = access(codes[a]), let accessB = access(codes[b]) else { continue }
                    if accessA.conflicts(with: accessB) && !after[a][b] && !after[b][a] {
                        expected.append(Ambiguity(first: first, second: second))
                    }
                }
            }
            #expect(schedule.ambiguities() == expected)
        }
    }
}

extension AmbiguityTests {
    @Test("Systems marked ambiguous still run one after another, in the order written")
    func markedStillOrdered() {
        let schedule = Schedule {
            DragWriter()
            GravityWriter().ambiguous(with: DragWriter.self)
        }
        let names: [String] = ["DragWriter", "GravityWriter"]
        let waves: [[Int]] = [[0], [1]]
        #expect(schedule.names == names)
        #expect(schedule.waves == waves)
    }

    @Test("A schedule marked ambiguous with a set marks each of its systems")
    func scheduleMarked() {
        let schedule = Schedule {
            Schedule {
                GravityWriter()
                VelocityReader().after(GravityWriter.self)
            }
            .ambiguous(with: DragWriter.self)
            DragWriter()
        }
        #expect(schedule.ambiguities().isEmpty)
    }
}
