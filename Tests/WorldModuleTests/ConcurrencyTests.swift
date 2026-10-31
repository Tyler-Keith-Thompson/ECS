// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import Testing
import WorldModule

struct Tally: Resource, Equatable { var count = 0 }
struct Flash: Event, Equatable { var strength: Int }
enum FlashReader {}

@Suite("Concurrent changes")
struct ConcurrencyTests {
    @Test("Accesses conflict when one writes what the other reads or writes, and not otherwise")
    func conflicts() {
        let readsPosition = Access.reads(Position.self)
        let writesPosition = Access.writes(Position.self)
        let writesVelocity = Access.writes(Velocity.self)
        let readsClock = Access.reads(resources: Clock.self)
        let writesClock = Access.writes(resources: Clock.self)
        #expect(!readsPosition.conflicts(with: readsPosition))
        #expect(readsPosition.conflicts(with: writesPosition))
        #expect(writesPosition.conflicts(with: readsPosition))
        #expect(writesPosition.conflicts(with: writesPosition))
        #expect(!writesPosition.conflicts(with: writesVelocity))
        #expect(!readsClock.conflicts(with: readsClock))
        #expect(readsClock.conflicts(with: writesClock))
        #expect(!writesClock.conflicts(with: writesPosition))
        #expect(!Access().conflicts(with: writesPosition))
        #expect(Access.sends(Flash.self).conflicts(with: .readsEvents(Flash.self, by: FlashReader.self)))
        #expect(!Access.readsEvents(Flash.self, by: FlashReader.self).conflicts(with: .readsEvents(Flash.self, by: ConcurrencyTests.self)))
    }

    @Test("Concurrent changes give the world a serial run gives")
    func agreesWithSerial() {
        var world = World()
        for value in 0 ..< 2_000 {
            let entity = world.spawn(Position(x: 0, y: 0), Velocity(dx: Double(value), dy: 1), Health(value))
            if value.isMultiple(of: 2) { world.insert(Name("\(value)"), into: entity) }
        }
        world.resources.insert(Tally())
        world.resources.insert(Clock(ticks: 0))
        let movement = ConcurrentChange(access: .reads(Velocity.self).writes(Position.self)) { world in
            world.update(Position.self, reading: Velocity.self) { position, row in position.x += row.components.dx }
        }
        let aging = ConcurrentChange(access: .writes(Health.self).reads(resources: Clock.self)) { world in
            let ticks = world.resources[Clock.self].ticks
            world.update(Health.self) { health, _ in health.current += 1 + ticks }
        }
        let counting = ConcurrentChange(access: .reads(Name.self).writes(resources: Tally.self)) { world in
            world.resources[Tally.self].count = world.query(Name.self).count
        }
        var serial = world
        for change in [movement, aging, counting] { change.body(&serial) }
        world.runConcurrently([movement, aging, counting])
        #expect(world.snapshot(Position.self, Velocity.self, Health.self, Name.self) == serial.snapshot(Position.self, Velocity.self, Health.self, Name.self))
        #expect(world.resources[Tally.self] == serial.resources[Tally.self])
        #expect(world.resources[Tally.self].count == 1_000)
    }

    @Test("Concurrent changes can insert and remove the component types they write, and create resources")
    func insertAndRemove() {
        var world = World()
        let first = world.spawn(Health(1))
        let second = world.spawn(Name("n"))
        world.runConcurrently([
            ConcurrentChange(access: .writes(Frozen.self)) { world in world.insert(Frozen(), into: first) },
            ConcurrentChange(access: .writes(Name.self)) { world in world.remove(Name.self, from: second) },
            ConcurrentChange(access: .writes(resources: Tally.self)) { world in world.resources.insert(Tally(count: 3)) },
        ])
        #expect(world.contains(Frozen.self, in: first))
        #expect(!world.contains(Name.self, in: second))
        #expect(world.resources[Tally.self].count == 3)
    }

    @Test("Concurrent changes can send and read events they declare")
    func events() {
        var world = World()
        world.send(Flash(strength: 1))
        world.resources.insert(Tally())
        world.runConcurrently([
            ConcurrentChange(access: .sends(Flash.self)) { world in world.send(Flash(strength: 2)) },
            ConcurrentChange(access: .writes(resources: Tally.self)) { world in world.resources[Tally.self].count += 1 },
        ])
        world.runConcurrently([
            ConcurrentChange(access: Access.readsEvents(Flash.self, by: FlashReader.self).writes(resources: Tally.self)) { world in
                world.resources[Tally.self].count += world.readEvents(Flash.self, by: FlashReader.self).map(\.strength).reduce(0, +)
            },
        ])
        #expect(world.resources[Tally.self].count == 4)
        let unread = Array(world.readEvents(Flash.self, by: FlashReader.self))
        let expected: [Flash] = []
        #expect(unread == expected)
    }

    @Test("No changes leave the world as it was")
    func none() {
        var world = World()
        let entity = world.spawn(Health(1))
        world.runConcurrently([])
        #expect(world[Health.self, of: entity] == Health(1))
    }

    @Test("Writing through concurrent changes copies nothing another world shares, and leaves that world unchanged")
    func copies() {
        var world = World()
        let entity = world.spawn(Health(1), Name("a"))
        let copy = world
        world.runConcurrently([
            ConcurrentChange(access: .writes(Health.self)) { world in world[Health.self, of: entity].current = 5 },
            ConcurrentChange(access: .writes(Name.self)) { world in world[Name.self, of: entity] = Name("b") },
        ])
        #expect(copy[Health.self, of: entity] == Health(1))
        #expect(copy[Name.self, of: entity] == Name("a"))
        #expect(world[Health.self, of: entity] == Health(5))
        #expect(world[Name.self, of: entity] == Name("b"))
    }

    @Test("Conflicting concurrent changes trap", .tags(.precondition))
    func conflictTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.runConcurrently([
                ConcurrentChange(access: .writes(Health.self)) { _ in },
                ConcurrentChange(access: .reads(Health.self)) { _ in },
            ])
        }
    }

    @Test("A concurrent change that writes a type its access does not list traps", .tags(.precondition))
    func undeclaredWriteTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let entity = world.spawn(Health(1), Name("n"))
            world.runConcurrently([
                ConcurrentChange(access: .writes(Health.self)) { world in world[Name.self, of: entity] = Name("m") },
                ConcurrentChange(access: Access()) { _ in },
            ])
        }
    }

    @Test("A concurrent change that spawns traps", .tags(.precondition))
    func spawnTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.runConcurrently([
                ConcurrentChange(access: .writes(Health.self)) { world in world.spawn(Health(1)) },
                ConcurrentChange(access: Access()) { _ in },
            ])
        }
    }
}
