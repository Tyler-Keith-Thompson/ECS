// Each test is self-contained: the systems it runs are declared inside it or below.

import ECSTestSupport
import Systems
import Testing
import WorldModule

/// Writes Position; conflicts with Steer.
struct Glide: System {
    var access: Access? { .writes(Position.self) }
    func run(in world: inout World) {}
}

/// Reads Position and writes Velocity.
struct Steer: System {
    var access: Access? { .reads(Position.self).writes(Velocity.self) }
    func run(in world: inout World) {}
}

/// Writes Health; conflicts with neither.
struct Mend: System {
    var access: Access? { .writes(Health.self) }
    func run(in world: inout World) {}
}

/// Removes the world's SystemProfile.
struct StopProfiling: System {
    func run(in world: inout World) {
        _ = world.resources.remove(SystemProfile.self)
    }
}

@Suite("Profiling")
struct ProfilingTests {
    @Test("A profile records each system's runs, in the order systems first ran")
    func records() {
        let frame = Schedule {
            Glide()
            Steer()
            Mend()
        }
        var world = World()
        world.resources.insert(SystemProfile())
        for _ in 0 ..< 3 { frame.run(on: &world) }
        let timings = world.resources[SystemProfile.self].timings
        let names = timings.map(\.name)
        let runs = timings.map(\.runs)
        let expectedNames: [String] = ["Glide", "Mend", "Steer"]
        let expectedRuns: [Int] = [3, 3, 3]
        #expect(names == expectedNames)
        #expect(runs == expectedRuns)
        for timing in timings {
            #expect(timing.total >= timing.longest)
            #expect(timing.longest >= timing.latest)
            #expect(timing.latest >= .zero)
            #expect(timing.average <= timing.longest)
        }
    }

    @Test("Serial runs record the same systems as concurrent ones, and skipped systems record nothing")
    func serialAndSkipped() {
        let frame = Schedule {
            Glide()
            Mend().runIf { _ in false }
        }
        var world = World()
        world.resources.insert(SystemProfile())
        frame.runSerially(on: &world)
        let names = world.resources[SystemProfile.self].timings.map(\.name)
        let expected: [String] = ["Glide"]
        #expect(names == expected)
    }

    @Test("Copies of one system are timed apart")
    func copies() {
        let frame = Schedule {
            Glide()
            Glide()
        }
        var world = World()
        world.resources.insert(SystemProfile())
        frame.run(on: &world)
        let runs = world.resources[SystemProfile.self].timings.map(\.runs)
        let expected: [Int] = [1, 1]
        #expect(runs == expected)
    }

    @Test("Without a profile nothing is recorded, and a system may remove the profile")
    func withoutProfile() {
        let frame = Schedule {
            Glide()
            StopProfiling()
            Mend().after(StopProfiling.self)
        }
        var world = World()
        frame.run(on: &world)
        #expect(!world.resources.contains(SystemProfile.self))
        world.resources.insert(SystemProfile())
        frame.run(on: &world)
        #expect(!world.resources.contains(SystemProfile.self))
    }

    @Test("A new profile holds no timings")
    func newProfile() {
        let profile = SystemProfile()
        let none: [SystemTiming] = []
        #expect(profile.timings == none)
    }

    @Test("The DOT graph labels systems and draws constraints solid, conflicts dashed, implied arcs not at all")
    func dot() {
        let frame = Schedule {
            Glide()
            Steer()
            Mend().after(Steer.self)
            Glide().after(Mend.self)
        }
        var dot = ""
        frame.writeDOT(to: &dot)
        let expected = """
            digraph {
            \t0 [label=Glide];
            \t1 [label=Steer];
            \t2 [label=Mend];
            \t3 [label=Glide];
            \t0 -> 1 [style=dashed];
            \t1 -> 2;
            \t2 -> 3;
            }

            """
        #expect(dot == expected)
    }

    @Test("An empty schedule's DOT graph has no nodes")
    func emptyDOT() {
        var dot = ""
        Schedule {}.writeDOT(to: &dot)
        let expected = "digraph {\n}\n"
        #expect(dot == expected)
    }
}
