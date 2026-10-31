// Each test is self-contained: the systems it runs are declared inside it or below, and record
// what happened in a resource.

import ECSTestSupport
import Systems
import Testing
import WorldModule

/// What `Prepared` did, in order.
struct PreparationLog: Resource { var entries: [String] = [] }

/// Logs its initialization and each run.
struct Prepared: System {
    func initialize(in world: inout World) {
        if !world.resources.contains(PreparationLog.self) {
            world.resources.insert(PreparationLog())
        }
        world.resources[PreparationLog.self].entries.append("initialize")
    }

    func run(in world: inout World) {
        world.resources[PreparationLog.self].entries.append("run")
    }
}

/// Uses the default initialization.
struct Unprepared: System {
    func run(in world: inout World) {}
}

@Suite("Schedule: initializing systems")
struct InitializationTests {
    @Test("A schedule initializes each system once per world, before the system first runs")
    func oncePerWorld() {
        let schedule = Schedule { Prepared() }
        var world = World()
        schedule.run(on: &world)
        schedule.run(on: &world)
        var other = World()
        schedule.run(on: &other)
        let expected: [String] = ["initialize", "run", "run"]
        let expectedOther: [String] = ["initialize", "run"]
        #expect(world.resources[PreparationLog.self].entries == expected)
        #expect(other.resources[PreparationLog.self].entries == expectedOther)
    }

    @Test("A system its condition skips is still initialized only once, before it first runs")
    func skippedOnce() {
        let schedule = Schedule {
            Prepared().runIf { world in world.resources.contains(Clock.self) }
        }
        var world = World()
        schedule.run(on: &world)
        schedule.run(on: &world)
        world.resources.insert(Clock(ticks: 0))
        schedule.run(on: &world)
        schedule.run(on: &world)
        let expected: [String] = ["initialize", "run", "run"]
        #expect(world.resources[PreparationLog.self].entries == expected)
    }

    @Test("A copy of a world keeps its systems initialized")
    func copyKeepsInitialization() {
        let schedule = Schedule { Prepared() }
        var world = World()
        schedule.run(on: &world)
        var copy = world
        schedule.run(on: &copy)
        let expected: [String] = ["initialize", "run", "run"]
        #expect(copy.resources[PreparationLog.self].entries == expected)
    }

    @Test("The default initialization leaves the world unchanged")
    func defaultDoesNothing() {
        var world = World()
        let entity = world.spawn(Health(3))
        Unprepared().initialize(in: &world)
        let expected: Health = Health(3)
        #expect(world.count == 1)
        #expect(world[Health.self, of: entity] == expected)
        #expect(!world.resources.contains(Clock.self))
    }
}
