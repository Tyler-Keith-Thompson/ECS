// How a schedule groups its systems into waves that run at the same time. Self-contained.

import ECSTestSupport
import PropertyBased
import Systems
import Testing
import WorldModule

/// A system whose access is whatever it was made with.
struct Declared: System {
    let access: Access?
    func run(in world: inout World) {}
}

struct WritesFirst: System {
    var access: Access? { .writes(First.self) }
    func run(in world: inout World) {}
}

struct ReadsFirst: System {
    var access: Access? { .reads(First.self) }
    func run(in world: inout World) {}
}

struct WritesSecond: System {
    var access: Access? { .writes(Second.self) }
    func run(in world: inout World) {}
}

struct Exclusive: System {
    func run(in world: inout World) {}
}

@Suite("Schedule: waves")
struct WaveTests {
    @Test("An empty schedule has no waves")
    func empty() {
        let schedule = Schedule {}
        #expect(schedule.waves.isEmpty)
    }

    @Test("Systems that do not conflict share a wave, even when not next to each other")
    func nonAdjacent() {
        let schedule = Schedule {
            WritesFirst()
            ReadsFirst()
            WritesSecond()
        }
        let expected: [[Int]] = [[0, 2], [1]]
        #expect(schedule.waves == expected)
    }

    @Test("A constraint puts a system in a later wave than the one it follows")
    func constraint() {
        let schedule = Schedule {
            WritesFirst()
            WritesSecond().after(WritesFirst.self)
        }
        let expected: [[Int]] = [[0], [1]]
        #expect(schedule.waves == expected)
    }

    @Test("A system without an access runs in a wave of its own, between the systems around it")
    func exclusive() {
        let schedule = Schedule {
            WritesFirst()
            Exclusive()
            WritesSecond()
        }
        let expected: [[Int]] = [[0], [1], [2]]
        #expect(schedule.waves == expected)
    }

    @Test("Readers of one type share a wave")
    func readers() {
        let schedule = Schedule {
            ReadsFirst()
            ReadsFirst()
            WritesFirst()
        }
        let expected: [[Int]] = [[0, 1], [2]]
        #expect(schedule.waves == expected)
    }

    @Test("Each wave holds systems that do not conflict, each one wave after its latest dependency", .tags(.randomized))
    func wavesAreLayers() async {
        // Each system: per type of First, Second and Third, 0 = untouched, 1 = read, 2 = written;
        // a 3 in the first slot means the system has no access.
        let systems = Gen.int(in: 0 ... 3).array(of: 3 ... 3).array(of: 0 ... 8)
        await propertyCheck(count: 300, input: systems) { specifications in
            func access(_ specification: [Int]) -> Access? {
                if specification[0] == 3 { return nil }
                var access = Access()
                if specification[0] == 1 { access = access.reads(First.self) }
                if specification[0] == 2 { access = access.writes(First.self) }
                if specification[1] == 1 { access = access.reads(Second.self) }
                if specification[1] >= 2 { access = access.writes(Second.self) }
                if specification[2] == 1 { access = access.reads(Third.self) }
                if specification[2] >= 2 { access = access.writes(Third.self) }
                return access
            }
            let accesses = specifications.map(access)
            func conflict(_ first: Int, _ second: Int) -> Bool {
                guard let a = accesses[first], let b = accesses[second] else { return true }
                return a.conflicts(with: b)
            }
            let schedule = Schedule {
                for access in accesses { Declared(access: access) }
            }
            var waveOf: [Int: Int] = [:]
            for (wave, members) in schedule.waves.enumerated() {
                #expect(!members.isEmpty)
                for member in members { waveOf[member] = wave }
            }
            #expect(waveOf.count == accesses.count)
            for later in accesses.indices {
                var latest = -1
                for earlier in 0 ..< later where conflict(later, earlier) {
                    #expect(waveOf[earlier]! < waveOf[later]!)
                    latest = max(latest, waveOf[earlier]!)
                }
                #expect(waveOf[later] == latest + 1)
            }
        }
    }
}
