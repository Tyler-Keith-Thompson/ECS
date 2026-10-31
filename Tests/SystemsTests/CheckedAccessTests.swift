// Each test is self-contained: the systems it runs are declared inside it or below.

import ECSTestSupport
import Systems
import Testing
import WorldModule

/// Declares reading Position, then reads Health too.
struct PeekAtHealth: System {
    var access: Access? { .reads(Position.self) }

    func run(in world: inout World) {
        _ = world.query(Health.self).map(\.entity)
    }
}

/// Declares reading Gravity, then reads Clock too.
struct PeekAtClock: System {
    var access: Access? { .reads(resources: Gravity.self) }

    func run(in world: inout World) {
        _ = world.resources.contains(Clock.self)
    }
}

/// Declares reading Clock, then changes it.
struct WindClock: System {
    var access: Access? { .reads(resources: Clock.self) }

    func run(in world: inout World) {
        world.resources[Clock.self].ticks += 1
    }
}

/// Counts ticks on the Clock, which it declares writing.
struct CountTicks: System {
    var access: Access? { .writes(resources: Clock.self) }

    func run(in world: inout World) {
        world.resources[Clock.self].ticks += 1
    }
}

/// Reads and writes only what it declares, skipping disabled entities as queries do.
struct Honest: System {
    var access: Access? { .reads(Velocity.self).writes(Position.self).writes(resources: Clock.self) }

    func run(in world: inout World) {
        world.update(Position.self, reading: Velocity.self) { position, row in
            position.x += row.components.dx
        }
        world.resources[Clock.self].ticks += 1
    }
}

/// Declares nothing, so it may reach anything.
struct Anything: System {
    func run(in world: inout World) {
        world.resources.insert(Gravity(acceleration: 2))
        _ = world.query(Health.self).map(\.entity)
    }
}

@Suite("Checked accesses")
struct CheckedAccessTests {
    @Test("Systems that reach only what they declare, or declare nothing, run as before")
    func honestSystems() {
        let frame = Schedule {
            Honest()
            Anything()
        }
        var world = World()
        world.resources.insert(Clock(ticks: 0))
        let mover = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let disabled = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Disabled())
        frame.run(on: &world)
        frame.runSerially(on: &world)
        let expectedTicks = 2
        #expect(world.resources[Clock.self].ticks == expectedTicks)
        #expect(world[Position.self, of: mover] == Position(x: 2, y: 0))
        #expect(world[Position.self, of: disabled] == Position(x: 0, y: 0))
        #expect(world.resources[Gravity.self] == Gravity(acceleration: 2))
    }

    @Test("Outside a system's run, the world is not restricted")
    func liftedAfterRun() {
        let frame = Schedule {
            Honest()
        }
        var world = World()
        world.resources.insert(Clock(ticks: 0))
        frame.run(on: &world)
        world.resources.insert(Gravity(acceleration: 1))
        let entity = world.spawn(Health(3))
        #expect(world[Health.self, of: entity] == Health(3))
    }

    @Test("A system reading a component type its access does not list traps in debug builds")
    func undeclaredComponent() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.spawn(Position(x: 0, y: 0), Health(1))
            Schedule { PeekAtHealth() }.run(on: &world)
        }
    }

    @Test("A system reading a resource type its access does not list traps in debug builds")
    func undeclaredResource() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.resources.insert(Gravity(acceleration: 1))
            world.resources.insert(Clock(ticks: 0))
            Schedule { PeekAtClock() }.run(on: &world)
        }
    }

    @Test("A system writing a resource its access lists only as read traps in debug builds")
    func resourceReadOnly() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.resources.insert(Clock(ticks: 0))
            Schedule { WindClock() }.run(on: &world)
        }
    }

    @Test("A system sharing a wave traps on an undeclared read as one running alone does")
    func undeclaredWhileConcurrent() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.resources.insert(Clock(ticks: 0))
            world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Health(1))
            Schedule {
                PeekAtHealth()
                CountTicks()
            }.run(on: &world)
        }
    }
}

/// Declares reading Position and writing Clock only, then reads the Disabled and Prefab markers
/// of two entities, counting the markers found on the Clock.
struct PeekAtMarkers: System {
    let disabled: Entity
    let prefab: Entity
    var access: Access? { .reads(Position.self).writes(resources: Clock.self) }

    func run(in world: inout World) {
        var found = 0
        if world.contains(Disabled.self, in: disabled) { found += 1 }
        if world.contains(Prefab.self, in: prefab) { found += 1 }
        world.resources[Clock.self].ticks = found
    }
}

extension CheckedAccessTests {
    @Test("A system can read Disabled and Prefab without listing them in its access")
    func markersAlwaysReadable() {
        var world = World()
        world.resources.insert(Clock(ticks: 0))
        let disabled = world.spawn(Position(x: 1, y: 0), Disabled())
        let prefab = world.spawn(Position(x: 2, y: 0), Prefab())
        Schedule { PeekAtMarkers(disabled: disabled, prefab: prefab) }.run(on: &world)
        let expected: Int = 2
        #expect(world.resources[Clock.self].ticks == expected)
    }
}
