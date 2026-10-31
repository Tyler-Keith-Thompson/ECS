// Each test is self-contained: the systems it orders are declared inside it or below, and record
// the order they run in a resource.

import ECSTestSupport
import Systems
import Testing
import WorldModule

/// The names of the systems that ran, in order.
struct RunLog: Resource { var names: [String] = [] }

struct Alpha: System { func run(in world: inout World) { world.resources[RunLog.self].names.append("Alpha") } }
struct Beta: System { func run(in world: inout World) { world.resources[RunLog.self].names.append("Beta") } }
struct Gamma: System { func run(in world: inout World) { world.resources[RunLog.self].names.append("Gamma") } }
struct Delta: System { func run(in world: inout World) { world.resources[RunLog.self].names.append("Delta") } }

@Suite("Schedule")
struct ScheduleTests {
    @Test("Unconstrained systems run in the order they are written")
    func writtenOrder() {
        let schedule = Schedule {
            Gamma()
            Alpha()
            Beta()
        }
        var world = World()
        world.resources.insert(RunLog())
        schedule.run(on: &world)
        let expected = ["Gamma", "Alpha", "Beta"]
        #expect(schedule.names == expected)
        #expect(world.resources[RunLog.self].names == expected)
    }

    @Test("An empty schedule runs nothing")
    func empty() {
        let schedule = Schedule {}
        var world = World()
        world.resources.insert(RunLog())
        schedule.run(on: &world)
        let expected: [String] = []
        #expect(schedule.names == expected)
        #expect(world.resources[RunLog.self].names == expected)
    }

    @Test("after moves the named system up to run just before the constrained one")
    func after() {
        let schedule = Schedule {
            Alpha()
            Beta().after(Delta.self)
            Gamma()
            Delta()
        }
        let expected = ["Alpha", "Delta", "Beta", "Gamma"]
        #expect(schedule.names == expected)
    }

    @Test("before moves the constrained system up to run just before the named one")
    func before() {
        let schedule = Schedule {
            Alpha()
            Beta()
            Gamma().before(Beta.self)
        }
        let expected = ["Alpha", "Gamma", "Beta"]
        #expect(schedule.names == expected)
    }

    @Test("A constraint already satisfied by the written order changes nothing")
    func satisfied() {
        let schedule = Schedule {
            Alpha()
            Beta().after(Alpha.self)
            Gamma().before(Delta.self)
            Delta()
        }
        let expected = ["Alpha", "Beta", "Gamma", "Delta"]
        #expect(schedule.names == expected)
    }

    @Test("Constraints chain transitively")
    func chain() {
        let schedule = Schedule {
            Alpha().after(Beta.self)
            Beta().after(Gamma.self)
            Gamma().after(Delta.self)
            Delta()
        }
        let expected = ["Delta", "Gamma", "Beta", "Alpha"]
        #expect(schedule.names == expected)
    }

    @Test("A constraint naming a type with no system in the schedule is ignored")
    func absentType() {
        let schedule = Schedule {
            Alpha().after(Delta.self)
            Beta().before(Gamma.self)
        }
        let expected = ["Alpha", "Beta"]
        #expect(schedule.names == expected)
    }

    @Test("A constraint naming the system's own type does not order it against itself")
    func ownType() {
        let schedule = Schedule {
            Alpha().after(Alpha.self)
            Beta()
        }
        let expected = ["Alpha", "Beta"]
        #expect(schedule.names == expected)
    }

    @Test("A constraint orders against every system of the named type")
    func everyInstance() {
        let schedule = Schedule {
            Gamma().after(Alpha.self)
            Alpha()
            Beta()
            Alpha()
        }
        let expected = ["Alpha", "Alpha", "Gamma", "Beta"]
        #expect(schedule.names == expected)
    }

    @Test("Nested schedules, conditions and loops contribute their systems in place")
    func builder() {
        let inner = Schedule {
            Beta()
            Gamma()
        }
        let includeDelta = true
        let includeAlpha = false
        let schedule = Schedule {
            inner
            if includeAlpha { Alpha() }
            if includeDelta { Delta() } else { Alpha() }
            for _ in 0 ..< 2 { Alpha() }
        }
        let expected = ["Beta", "Gamma", "Delta", "Alpha", "Alpha"]
        #expect(schedule.names == expected)
    }

    @Test("The checked spelling throws CyclicOrdering for a cycle")
    func checkedCycle() throws {
        #expect(throws: CyclicOrdering()) {
            try Schedule(checked: [
                Alpha().after(Beta.self),
                Beta().after(Gamma.self),
                Gamma().after(Alpha.self),
            ])
        }
        #expect(throws: CyclicOrdering()) {
            try Schedule(checked: [
                Alpha().before(Beta.self),
                Beta().before(Alpha.self),
            ])
        }
        let schedule = try Schedule(checked: [
            Alpha().after(Beta.self),
            ScheduledSystem(Beta()),
        ])
        let expected = ["Beta", "Alpha"]
        #expect(schedule.names == expected)
    }

    @Test("The plain spelling traps on a cycle", .tags(.precondition))
    func plainCycleTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Schedule {
                Alpha().after(Beta.self)
                Beta().after(Alpha.self)
            }
        }
    }

    @Test("Systems see the changes of the systems before them")
    func seesEarlierWrites() {
        struct Spawner: System {
            func run(in world: inout World) { world.spawn(Health(1)) }
        }
        struct Healer: System {
            func run(in world: inout World) {
                world.update(Health.self) { health, _ in health.current += 1 }
            }
        }
        let schedule = Schedule {
            Healer().after(Spawner.self)
            Spawner()
        }
        var world = World()
        schedule.run(on: &world)
        schedule.run(on: &world)
        let values = world.query(Health.self).map(\.1.current).sorted()
        #expect(values == [2, 3])
    }
}
