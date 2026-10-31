// Each test is self-contained apart from the systems declared at the bottom of this file.

import ECSTestSupport
import Systems
import Testing
import WorldModule

/// Which entities' Health changed since the observer's last run, recorded each time it runs.
struct Observed: Resource { var runs: [[Entity]] = [] }

struct HealthObserver: System {
    func run(in world: inout World) {
        let changed = world.query(Health.self).changed(Health.self).map(\.entity).sorted()
        world.resources[Observed.self].runs.append(changed)
    }
}

/// Damages the entity named in its resource, once per run.
struct Target: Resource { var entity: Entity? }

struct Damage: System {
    func run(in world: inout World) {
        guard let entity = world.resources[Target.self].entity else { return }
        world[Health.self, of: entity].current -= 1
    }
}

struct SelfHealer: System {
    func run(in world: inout World) {
        let changedBeforeHealing = world.query(Health.self).changed(Health.self).count
        world.update(Health.self) { health, _ in health.current += 1 }
        world.resources[Observed.self].runs.append(Array(repeating: Entity(index: 0, generation: 0), count: changedBeforeHealing))
    }
}

@Suite("Schedule: change detection")
struct ChangeDetectionScheduleTests {
    @Test("A system's first run sees everything; later runs see only changes made since")
    func firstRunSeesAll() {
        var world = World()
        world.resources.insert(Observed())
        world.resources.insert(Target(entity: nil))
        let a = world.spawn(Health(1))
        let b = world.spawn(Health(1))
        let schedule = Schedule { HealthObserver() }
        schedule.run(on: &world)
        schedule.run(on: &world)
        world[Health.self, of: b].current = 5
        schedule.run(on: &world)
        let expected: [[Entity]] = [[a, b], [], [b]]
        #expect(world.resources[Observed.self].runs == expected)
    }

    @Test("A system sees changes from systems after it last time and before it this time")
    func ordering() {
        var world = World()
        world.resources.insert(Observed())
        let a = world.spawn(Health(1))
        world.resources.insert(Target(entity: a))
        let observerFirst = Schedule {
            HealthObserver()
            Damage()
        }
        observerFirst.run(on: &world)
        observerFirst.run(on: &world)
        let observerLast = Schedule {
            Damage()
            HealthObserver()
        }
        var other = World()
        other.resources.insert(Observed())
        let b = other.spawn(Health(1))
        other.resources.insert(Target(entity: b))
        observerLast.run(on: &other)
        observerLast.run(on: &other)
        let expectedFirst: [[Entity]] = [[a], [a]]
        let expectedLast: [[Entity]] = [[b], [b]]
        #expect(world.resources[Observed.self].runs == expectedFirst)
        #expect(other.resources[Observed.self].runs == expectedLast)
    }

    @Test("A system does not see its own changes on its next run")
    func notOwnChanges() {
        var world = World()
        world.resources.insert(Observed())
        world.spawn(Health(1))
        let schedule = Schedule { SelfHealer() }
        schedule.run(on: &world)
        schedule.run(on: &world)
        schedule.run(on: &world)
        let counts = world.resources[Observed.self].runs.map(\.count)
        #expect(counts == [1, 0, 0])
    }

    @Test("Running a schedule restores the world's lastRun afterwards")
    func restoresLastRun() {
        var world = World()
        world.resources.insert(Observed())
        let outer = ChangeTick(7)
        world.lastRun = outer
        Schedule { HealthObserver() }.run(on: &world)
        #expect(world.lastRun == outer)
    }

    @Test("A copy of a world remembers each system's last run as the original did", .tags(.copyOnWrite))
    func copiesRemember() {
        var world = World()
        world.resources.insert(Observed())
        world.spawn(Health(1))
        let schedule = Schedule { HealthObserver() }
        schedule.run(on: &world)
        var copy = world
        schedule.run(on: &copy)
        let expected: [[Entity]] = [[Entity(index: 0, generation: 0)], []]
        #expect(copy.resources[Observed.self].runs == expected)
    }
}

extension ChangeDetectionScheduleTests {
    @Test("The change tick advances once per wave that runs a system, and once more after the last")
    func tickPerWave() {
        func advance(of schedule: Schedule) -> UInt64 {
            var world = World()
            world.resources.insert(Observed())
            let before = world.changeTick.value
            schedule.run(on: &world)
            return world.changeTick.value - before
        }
        let running = Schedule {
            HealthObserver()
            HealthObserver()
        }
        let skipped = Schedule {
            HealthObserver().runIf { _ in false }
        }
        let three: UInt64 = 3
        let one: UInt64 = 1
        #expect(advance(of: running) == three)
        #expect(advance(of: skipped) == one)
    }
}
