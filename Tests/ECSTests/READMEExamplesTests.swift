// The README's examples, verbatim, so the README cannot drift from the code.

import ECS
import Testing

struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }
struct Health: Component { var current: Int }
struct Frozen: Component {}
struct Clock: Resource { var ticks = 0 }

struct Movement: System {
    func run(in world: inout World) {
        world.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, row in
            position.x += row.components.dx
            position.y += row.components.dy
        }
    }
}

struct Reaper: System {
    func run(in world: inout World) {
        var commands = Commands()
        world.update(Health.self) { health, row in
            if health.current <= 0 { commands.despawn(row.entity) }
        }
        world.apply(commands)
    }
}

struct Tick: System {
    func run(in world: inout World) {
        world.resources[Clock.self].ticks += 1
    }
}

@Suite("README examples")
struct READMEExamplesTests {
    @Test("Usage")
    func usage() {
        var world = World()
        world.resources.insert(Clock())

        let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2), Health(current: 3))
        let wall = world.spawn(Position(x: 5, y: 0), Velocity(dx: 9, dy: 9), Frozen())
        let ghost = world.spawn(Health(current: 0))

        let tick = Schedule {
            Reaper().after(Movement.self)
            Movement()
            Tick()
        }
        tick.run(on: &world)

        print(tick.names)                     // ["Movement", "Reaper", "Tick"]
        print(world[Position.self, of: ball]) // Position(x: 1.0, y: 2.0)
        print(world[Position.self, of: wall]) // Position(x: 5.0, y: 0.0)
        print(world.contains(ghost))          // false
        print(world.resources[Clock.self])    // Clock(ticks: 1)

        for (entity, position, velocity) in world.query(Position.self, Velocity.self).without(Frozen.self) {
            print(entity, position, velocity)
        }

        #expect(tick.names == ["Movement", "Reaper", "Tick"])
        #expect(world[Position.self, of: ball].x == 1)
        #expect(world[Position.self, of: ball].y == 2)
        #expect(world[Position.self, of: wall].x == 5)
        #expect(!world.contains(ghost))
        #expect(world.resources[Clock.self].ticks == 1)
        #expect(world.query(Position.self, Velocity.self).without(Frozen.self).map(\.entity) == [ball])
    }
}
