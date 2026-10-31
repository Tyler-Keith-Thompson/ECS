// The README's examples, verbatim, so the README cannot drift from the code.

import ECS
import Testing

struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }
struct Health: Component { var current: Int }
struct Frozen: Component {}
struct Clock: Resource { var ticks = 0 }
struct Wind: Component { var speed: Double }
struct Current: Component { var speed: Double }
struct Anchored: Component {}

@System
struct Movement {
    func run(_ movers: Update<Position>.Over<Velocity>.Where<Without<Frozen>>) {
        movers { position, row in
            position.x += row.components.dx
            position.y += row.components.dy
        }
    }
}

@System
struct Reaper {
    func run(_ living: Query<Health>, commands: inout Commands) {
        for (entity, health) in living where health.current <= 0 {
            commands.despawn(entity)
        }
    }
}

@System
struct Tick {
    func run(clock: ResourceWriter<Clock>) {
        clock.value.ticks += 1
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

    @Test("Query values")
    func queryValues() {
        var world = World()
        let raft = world.spawn(Position(x: 0, y: 0), Wind(speed: 1), Current(speed: 2))
        let kite = world.spawn(Position(x: 0, y: 0), Wind(speed: 3))
        let buoy = world.spawn(Position(x: 0, y: 0), Current(speed: 4), Anchored())
        let rock = world.spawn(Position(x: 0, y: 0))

        let drifting = Query(AnyOf<Wind, Current>.self).without(Anchored.self)
        world.update(Position.self, over: drifting) { position, row in
            let (wind, current) = row.components
            position.x += (wind?.speed ?? 0) + (current?.speed ?? 0)
        }
        for (entity, position, (wind, current)) in world.query(Query(Position.self, AnyOf<Wind, Current>.self)) {
            print(entity, position, wind?.speed ?? 0, current?.speed ?? 0)
        }

        let expectedRaft = 3.0
        let expectedKite = 3.0
        let expectedStill = 0.0
        #expect(world[Position.self, of: raft].x == expectedRaft)
        #expect(world[Position.self, of: kite].x == expectedKite)
        #expect(world[Position.self, of: buoy].x == expectedStill)
        #expect(world[Position.self, of: rock].x == expectedStill)
    }
}
