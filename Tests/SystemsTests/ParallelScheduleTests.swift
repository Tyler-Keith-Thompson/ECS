// Each test is self-contained: the systems it runs are declared below.

import ECSTestSupport
import Systems
import Testing
import WorldModule

struct Score: Resource, Equatable { var points = 0 }
struct Paused2: Resource {}

struct Mover: System {
    var access: Access? { .reads(Velocity.self).writes(Position.self) }
    func run(in world: inout World) {
        world.update(Position.self, reading: Velocity.self) { position, row in position.x += row.components.dx }
    }
}

struct Ager: System {
    var access: Access? { .writes(Health.self).reads(resources: Clock.self) }
    func run(in world: inout World) {
        let ticks = world.resources[Clock.self].ticks
        world.update(Health.self) { health, _ in health.current -= 1 + ticks % 2 }
    }
}

/// Counts positions changed since its last run, into the score.
struct Scorer: System {
    var access: Access? { .reads(Position.self).writes(resources: Score.self) }
    func run(in world: inout World) {
        world.resources[Score.self].points += world.query(Position.self).changed(Position.self).count
    }
}

struct Ticker: System {
    var access: Access? { .writes(resources: Clock.self) }
    func run(in world: inout World) { world.resources[Clock.self].ticks += 1 }
}

/// Spawns and despawns, so it runs alone.
struct Reaper: System {
    func run(in world: inout World) {
        let dead = world.query(Health.self).filter { $0.1.current <= 0 }.map(\.entity)
        for entity in dead { world.despawn(entity) }
        world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Health(3))
    }
}

@Suite("Parallel schedules")
struct ParallelScheduleTests {
    @Test("Running a schedule in parallel gives the world running it serially gives, frame after frame")
    func agreesWithSerial() {
        let schedule = Schedule {
            Mover()
            Ager()
            Scorer()
            Reaper()
            Ticker()
            Mover().runIf { world in !world.resources.contains(Paused2.self) }
            Scorer()
        }
        var world = World()
        world.resources.insert(Score())
        world.resources.insert(Clock(ticks: 0))
        for value in 0 ..< 500 {
            world.spawn(Position(x: 0, y: 0), Velocity(dx: Double(value % 5), dy: 0), Health(value % 4 + 1))
        }
        var serial = world
        var parallel = world
        for frame in 0 ..< 8 {
            if frame == 4 {
                serial.resources.insert(Paused2())
                parallel.resources.insert(Paused2())
            }
            schedule.run(on: &serial)
            schedule.parallelRun(on: &parallel)
            #expect(parallel.snapshot(Position.self, Velocity.self, Health.self) == serial.snapshot(Position.self, Velocity.self, Health.self))
            #expect(parallel.resources[Score.self] == serial.resources[Score.self])
            #expect(parallel.resources[Clock.self] == serial.resources[Clock.self])
        }
    }

    @Test("Systems keep their declared access in a schedule, and systems without one have none")
    func accessKept() {
        let schedule = Schedule {
            Mover()
            Reaper()
        }
        #expect(schedule.systems[0].access != nil)
        #expect(schedule.systems[1].access == nil)
    }

    @Test("Parallel running restores the world's lastRun and advances its tick, as running does")
    func ticks() {
        let schedule = Schedule {
            Mover()
            Ticker()
        }
        var world = World()
        world.resources.insert(Clock(ticks: 0))
        let outer = ChangeTick(0)
        world.lastRun = outer
        let before = world.changeTick
        schedule.parallelRun(on: &world)
        #expect(world.lastRun == outer)
        #expect(world.changeTick > before)
    }
}
