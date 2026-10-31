// Each test is self-contained: the systems it runs are declared inside it or below, and record
// what they did in a resource.

import ECSTestSupport
import Synchronization
import Systems
import Testing
import WorldModule

struct Paused: Resource {}

/// The names of the systems that ran, in order.
struct ConditionLog: Resource { var names: [String] = [] }

struct Walk: System { func run(in world: inout World) { world.resources[ConditionLog.self].names.append("Walk") } }
struct Jump: System { func run(in world: inout World) { world.resources[ConditionLog.self].names.append("Jump") } }
struct Pause: System {
    func run(in world: inout World) {
        world.resources[ConditionLog.self].names.append("Pause")
        world.resources.insert(Paused())
    }
}

/// Records how many Health components changed since its last run.
struct ChangeCounter: System {
    func run(in world: inout World) {
        let changed = world.query(Health.self).changed(Health.self).count
        world.resources[ConditionLog.self].names.append("\(changed)")
    }
}

@Suite("Run conditions")
struct RunConditionTests {
    @Test("A system runs when its condition holds and is skipped when it does not")
    func holdsOrNot() {
        let schedule = Schedule {
            Walk().runIf { world in !world.resources.contains(Paused.self) }
            Jump()
        }
        var world = World()
        world.resources.insert(ConditionLog())
        schedule.run(on: &world)
        world.resources.insert(Paused())
        schedule.run(on: &world)
        let names = world.resources[ConditionLog.self].names
        let expected = ["Walk", "Jump", "Jump"]
        #expect(names == expected)
    }

    @Test("A system with several conditions runs only when all of them hold")
    func allConditions() {
        let schedule = Schedule {
            Walk()
                .runIf { world in world.resources.contains(Clock.self) }
                .runIf { world in !world.resources.contains(Paused.self) }
        }
        var world = World()
        world.resources.insert(ConditionLog())
        schedule.run(on: &world)
        world.resources.insert(Clock(ticks: 0))
        schedule.run(on: &world)
        world.resources.insert(Paused())
        schedule.run(on: &world)
        let names = world.resources[ConditionLog.self].names
        let expected = ["Walk"]
        #expect(names == expected)
    }

    @Test("Conditions are checked just before each system, after the systems before it ran")
    func checkedInTurn() {
        let schedule = Schedule {
            Walk()
            Pause()
            Jump().runIf { world in !world.resources.contains(Paused.self) }
        }
        var world = World()
        world.resources.insert(ConditionLog())
        schedule.run(on: &world)
        let names = world.resources[ConditionLog.self].names
        let expected = ["Walk", "Pause"]
        #expect(names == expected)
    }

    @Test("A schedule's condition applies to each of its systems, also when nested")
    func scheduleCondition() {
        let schedule = Schedule {
            Schedule {
                Walk()
                Pause()
                Jump()
            }
            .runIf { world in !world.resources.contains(Paused.self) }
            Walk()
        }
        var world = World()
        world.resources.insert(ConditionLog())
        schedule.run(on: &world)
        schedule.run(on: &world)
        let names = world.resources[ConditionLog.self].names
        let expected = ["Walk", "Pause", "Walk", "Walk"]
        #expect(names == expected)
    }

    @Test("A schedule's condition keeps its systems' order and constraints")
    func scheduleConditionKeepsOrder() {
        let schedule = Schedule {
            Jump().after(Walk.self)
            Walk()
        }
        .runIf { _ in true }
        let expected = ["Walk", "Jump"]
        #expect(schedule.names == expected)
    }

    @Test("A skipped system sees every change since it last ran, not since it was skipped")
    func skippedSeesEverything() {
        let schedule = Schedule {
            ChangeCounter().runIf { world in !world.resources.contains(Paused.self) }
        }
        var world = World()
        world.resources.insert(ConditionLog())
        let entity = world.spawn(Health(3))
        schedule.run(on: &world)
        world.resources.insert(Paused())
        world[Health.self, of: entity].current = 2
        schedule.run(on: &world)
        _ = world.resources.remove(Paused.self)
        schedule.run(on: &world)
        let names = world.resources[ConditionLog.self].names
        let expected = ["1", "1"]
        #expect(names == expected)
    }

    @Test("shouldRun reports whether every condition holds, and run ignores them")
    func shouldRunAndRun() {
        let system = Walk().runIf { _ in false }
        var world = World()
        world.resources.insert(ConditionLog())
        #expect(!system.shouldRun(in: world))
        #expect(ScheduledSystem(Walk()).shouldRun(in: world))
        system.run(in: &world)
        let names = world.resources[ConditionLog.self].names
        let expected = ["Walk"]
        #expect(names == expected)
    }
}

/// The conditions called, by number, gathered from whichever thread calls them.
final class ConditionCalls: Sendable {
    let numbers = Mutex<[Int]>([])
}

extension RunConditionTests {
    @Test("Several conditions are checked in the order they were added, stopping at the first that does not hold")
    func conditionsShortCircuit() {
        let calls = ConditionCalls()
        let system = Walk()
            .runIf { _ in calls.numbers.withLock { $0.append(1) }; return true }
            .runIf { _ in calls.numbers.withLock { $0.append(2) }; return false }
            .runIf { _ in calls.numbers.withLock { $0.append(3) }; return true }
        let world = World()
        let runs = system.shouldRun(in: world)
        let called = calls.numbers.withLock { $0 }
        let expected: [Int] = [1, 2]
        #expect(!runs)
        #expect(called == expected)
    }
}
