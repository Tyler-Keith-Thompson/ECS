// Each test is self-contained: the systems it runs are declared inside it or below.

import ECSTestSupport
import Systems
import Testing
import WorldModule

/// Main-actor state a main-actor system writes, as a user interface would hold.
@MainActor
final class Display {
    var lines: [String] = []

    nonisolated init() {}
}

/// Shows each entity's Health on a Display.
struct ShowHealth: MainActorSystem {
    let display: Display
    var access: Access? { .reads(Health.self) }

    @MainActor
    func run(in world: inout World) {
        let values = world.query(Health.self).map(\.1.current).sorted()
        display.lines.append(values.map(String.init).joined(separator: ","))
    }
}

/// Adds one to every Health.
struct Regenerate: System {
    var access: Access? { .writes(Health.self) }

    func run(in world: inout World) {
        world.update(Health.self) { health, _ in health.current += 1 }
    }
}

/// Moves every Position one to the right; conflicts with nothing ShowHealth touches.
struct Drift: System {
    var access: Access? { .writes(Position.self) }

    func run(in world: inout World) {
        world.update(Position.self) { position, _ in position.x += 1 }
    }
}

/// Speeds every Velocity up by one; conflicts with neither Drift nor ShowHealth.
struct Accelerate: System {
    var access: Access? { .writes(Velocity.self) }

    func run(in world: inout World) {
        world.update(Velocity.self) { velocity, _ in velocity.dx += 1 }
    }
}

/// Shows the number of entities with a Position, through system parameters.
@MainActor
@System
struct ShowCount {
    let display: Display

    func run(positions: Query<Position>) {
        var count = 0
        for _ in positions { count += 1 }
        display.lines.append("\(count)")
    }
}

@Suite("Main-actor systems")
struct MainActorSystemTests {
    @Test("A main-actor system runs on the main actor in its place in the schedule")
    @MainActor
    func runsInOrder() {
        let display = Display()
        let frame = Schedule {
            Regenerate()
            ShowHealth(display: display).after(Regenerate.self)
        }
        var world = World()
        world.spawn(Health(1))
        world.spawn(Health(5))
        frame.run(on: &world)
        frame.run(on: &world)
        let expected: [String] = ["2,6", "3,7"]
        #expect(display.lines == expected)
    }

    @Test("A main-actor system shares a wave with systems it does not conflict with, with the serial result")
    @MainActor
    func sharesWave() {
        let display = Display()
        let frame = Schedule {
            Drift()
            Accelerate()
            ShowHealth(display: display)
        }
        var world = World()
        world.spawn(Health(1), Position(x: 0, y: 0), Velocity(dx: 0, dy: 0))
        var serial = world
        frame.run(on: &world)
        frame.runSerially(on: &serial)
        let expected: [String] = ["1", "1"]
        #expect(display.lines == expected)
        #expect(world.snapshot(Position.self, Velocity.self, Health.self) == serial.snapshot(Position.self, Velocity.self, Health.self))
        let expectedPosition = Position(x: 1, y: 0)
        #expect(world.query(Position.self).map(\.1) == [expectedPosition])
    }

    @Test("@System makes a main-actor system of a @MainActor type")
    @MainActor
    func macro() {
        let display = Display()
        let frame = Schedule {
            ShowCount(display: display)
        }
        var world = World()
        world.spawn(Position(x: 0, y: 0))
        world.spawn(Position(x: 1, y: 0))
        frame.run(on: &world)
        let expected: [String] = ["2"]
        #expect(display.lines == expected)
        let runsOnMainActor = frame.systems.map(\.runsOnMainActor)
        let expectedRunsOnMainActor: [Bool] = [true]
        #expect(runsOnMainActor == expectedRunsOnMainActor)
    }

    @Test("Running a schedule holding a main-actor system off the main actor traps")
    func offMainActorTraps() async {
        await #expect(processExitsWith: .failure) {
            let display = Display()
            let frame = Schedule {
                ShowHealth(display: display)
            }
            await Task.detached {
                var world = World()
                frame.run(on: &world)
            }.value
        }
    }
}
