// The optional subscripts of a world and its resources. Each test is self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

/// What hooks saw through the optional subscript, in the order they ran.
private struct OptionalAccessLog: Resource {
    var entries: [String] = []
}

@Suite("World: optional access")
struct OptionalAccessTests {
    @Test("Reading an optional component gives the component an entity holds, or nil")
    func readComponent() {
        var world = World()
        let held = world.spawn(Health(3))
        let bare = world.spawn()
        let three: Health? = Health(3)
        #expect(world[Health?.self, of: held] == three)
        #expect(world[Health?.self, of: bare] == nil)
        #expect(world[Position?.self, of: held] == nil)
    }

    @Test("Assigning an optional component inserts, replaces in place, or removes it")
    func writeComponent() {
        var world = World()
        let entity = world.spawn()
        world[Health?.self, of: entity] = Health(1)
        let one = Health(1)
        #expect(world[Health.self, of: entity] == one)
        world[Health?.self, of: entity] = Health(2)
        let two = Health(2)
        #expect(world[Health.self, of: entity] == two)
        world[Health?.self, of: entity]?.current += 5
        let seven = Health(7)
        #expect(world[Health.self, of: entity] == seven)
        world[Health?.self, of: entity] = nil
        #expect(!world.contains(Health.self, in: entity))
        world[Health?.self, of: entity] = nil
        world[Health?.self, of: entity]?.current += 1
        #expect(!world.contains(Health.self, in: entity))
        #expect(world.contains(entity))
    }

    @Test("Inserting through the optional subscript runs insert hooks and adds required components; removing runs remove hooks; writing in place runs none")
    func componentHooks() {
        var world = World()
        world.resources.insert(OptionalAccessLog())
        world.onInsert(Health.self) { world, entity in
            world.resources[OptionalAccessLog.self].entries.append("insert \(world[Health.self, of: entity].current)")
        }
        world.onRemove(Health.self) { world, _, health in
            world.resources[OptionalAccessLog.self].entries.append("remove \(health.current)")
        }
        let entity = world.spawn()
        world[Health?.self, of: entity] = Health(1)
        world[Health?.self, of: entity]?.current = 2
        world[Health?.self, of: entity] = Health(3)
        world[Health?.self, of: entity] = nil
        let expected = ["insert 1", "remove 3"]
        #expect(world.resources[OptionalAccessLog.self].entries == expected)

        let avatar = world.spawn()
        world[Avatar?.self, of: avatar] = Avatar()
        #expect(world.contains(Position.self, in: avatar))
        #expect(world.contains(Avatar.self, in: avatar))
    }

    @Test("Writing an optional component in place marks it changed, and inserting marks it added")
    func componentTicks() {
        var world = World()
        let held = world.spawn(Health(1))
        let bare = world.spawn()
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world[Health?.self, of: held]?.current = 2
        world[Health?.self, of: bare] = Health(5)
        let both: Set<Entity> = [held, bare]
        let bareOnly: Set<Entity> = [bare]
        #expect(Set(world.query(Health.self).changed(Health.self, since: checkpoint).map(\.entity)) == both)
        #expect(Set(world.query(Health.self).added(Health.self, since: checkpoint).map(\.entity)) == bareOnly)
    }

    @Test("Reading an optional component of a stale entity traps")
    func readStaleTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let gone = world.spawn(Health(1))
            world.despawn(gone)
            _ = world[Health?.self, of: gone]
        }
    }

    @Test("Writing an optional component of a stale entity traps")
    func writeStaleTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let gone = world.spawn()
            world.despawn(gone)
            world[Health?.self, of: gone] = Health(1)
        }
    }

    @Test("Reading an optional resource gives the resource the world holds, or nil")
    func readResource() {
        var world = World()
        #expect(world.resources[Gravity?.self] == nil)
        world.resources.insert(Gravity(acceleration: -9.8))
        let gravity: Gravity? = Gravity(acceleration: -9.8)
        #expect(world.resources[Gravity?.self] == gravity)
        #expect(world.resources[Clock?.self] == nil)
    }

    @Test("Assigning an optional resource inserts, replaces or removes it, and writing through nil changes nothing")
    func writeResource() {
        var world = World()
        world.resources[Clock?.self]?.ticks += 1
        #expect(world.resources.isEmpty)
        world.resources[Clock?.self] = Clock(ticks: 1)
        let one = Clock(ticks: 1)
        #expect(world.resources[Clock.self] == one)
        world.resources[Clock?.self]?.ticks += 2
        let three = Clock(ticks: 3)
        #expect(world.resources[Clock.self] == three)
        world.resources[Clock?.self] = nil
        #expect(!world.resources.contains(Clock.self))
        world.resources[Clock?.self] = nil
        #expect(world.resources.isEmpty)
    }

    @Test("The optional subscripts agree with a dictionary under random writes", .tags(.randomized))
    func matchesDictionary() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            let entities = [world.spawn(), world.spawn(), world.spawn()]
            var expected: [Entity: Int] = [:]
            var expectedClock: Int?
            for _ in 0 ..< Int.random(in: 0 ... 60, using: &generator) {
                let entity = entities[Int.random(in: 0 ..< entities.count, using: &generator)]
                let value = Int.random(in: 0 ..< 10, using: &generator)
                switch Int.random(in: 0 ..< 6, using: &generator) {
                case 0:
                    world[Health?.self, of: entity] = Health(value)
                    expected[entity] = value
                case 1:
                    world[Health?.self, of: entity] = nil
                    expected[entity] = nil
                case 2:
                    world[Health?.self, of: entity]?.current += value
                    expected[entity] = expected[entity].map { $0 + value }
                case 3:
                    world.resources[Clock?.self] = Clock(ticks: value)
                    expectedClock = value
                case 4:
                    world.resources[Clock?.self] = nil
                    expectedClock = nil
                default:
                    world.resources[Clock?.self]?.ticks += value
                    expectedClock = expectedClock.map { $0 + value }
                }
            }
            for entity in entities {
                let held: Int? = world[Health?.self, of: entity]?.current
                #expect(held == expected[entity])
            }
            let clock: Int? = world.resources[Clock?.self]?.ticks
            #expect(clock == expectedClock)
        }
    }
}
