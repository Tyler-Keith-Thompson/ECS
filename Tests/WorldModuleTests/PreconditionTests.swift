// Exit tests: every trap of the plain spellings.

import ECSTestSupport
import Testing
import WorldModule

@Suite("World: traps")
struct PreconditionTests {
    @Test("Despawning a stale entity traps", .tags(.precondition))
    func despawnStale() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let entity = world.spawn()
            world.despawn(entity)
            world.despawn(entity)
        }
    }

    @Test("Inserting into a stale entity traps", .tags(.precondition))
    func insertStale() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let entity = world.spawn()
            world.despawn(entity)
            world.insert(Health(1), into: entity)
        }
    }

    @Test("Removing from a stale entity traps", .tags(.precondition))
    func removeStale() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let entity = world.spawn(Health(1))
            world.despawn(entity)
            world.remove(Health.self, from: entity)
        }
    }

    @Test("Reading a component an entity does not hold traps", .tags(.precondition))
    func readMissing() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let entity = world.spawn()
            _ = world[Health.self, of: entity]
        }
    }

    @Test("Reading a component of a stale entity traps", .tags(.precondition))
    func readStale() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let entity = world.spawn(Health(1))
            world.despawn(entity)
            _ = world[Health.self, of: entity]
        }
    }

    @Test("Writing a component an entity does not hold traps", .tags(.precondition))
    func writeMissing() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            _ = world.spawn(Health(1))
            let entity = world.spawn()
            world[Health.self, of: entity].current = 3
        }
    }

    @Test("Writing a component of a stale entity traps", .tags(.precondition))
    func writeStale() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let entity = world.spawn(Health(1))
            world.despawn(entity)
            world[Health.self, of: entity].current = 3
        }
    }

    @Test("Reading a missing resource traps", .tags(.precondition))
    func readMissingResource() async {
        await #expect(processExitsWith: .failure) {
            let resources = Resources()
            _ = resources[Clock.self]
        }
    }

    @Test("Writing a missing resource traps", .tags(.precondition))
    func writeMissingResource() async {
        await #expect(processExitsWith: .failure) {
            var resources = Resources()
            resources[Clock.self].ticks = 1
        }
    }

    @Test("An update that reads the type it writes traps", .tags(.precondition))
    func updateReadsWritten() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            _ = world.spawn(Health(1))
            world.update(Health.self, reading: Health.self) { _, _ in }
        }
    }

    @Test("An update that writes one type twice traps", .tags(.precondition))
    func updateWritesTwice() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            _ = world.spawn(Health(1))
            world.update(Health.self, Health.self) { _, _, _ in }
        }
    }

    @Test("A two-type update that reads a type it writes traps", .tags(.precondition))
    func updateTwoReadsWritten() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            _ = world.spawn(Health(1), Name("a"))
            world.update(Health.self, Name.self, reading: Name.self) { _, _, _ in }
        }
    }
}
