// The checked spellings: each throws its typed error and leaves the world unchanged.

import ECSTestSupport
import Testing
import WorldModule

@Suite("World: checked spellings")
struct CheckedTests {
    @Test("despawn(checked:) throws StaleEntity for a stale entity")
    func despawnChecked() throws {
        var world = World()
        let entity = world.spawn(Health(1))
        try world.despawn(checked: entity)
        #expect(throws: StaleEntity()) {
            try world.despawn(checked: entity)
        }
        #expect(world.count == 0)
    }

    @Test("insert(_:checkedInto:) throws StaleEntity for a stale entity and inserts nothing")
    func insertChecked() throws {
        var world = World()
        let entity = world.spawn()
        try world.insert(Health(1), checkedInto: entity)
        let one = Health(1)
        #expect(world[Health.self, of: entity] == one)
        world.despawn(entity)
        #expect(throws: StaleEntity()) {
            try world.insert(Health(2), checkedInto: entity)
        }
        #expect(world.count(of: Health.self) == 0)
    }

    @Test("remove(_:checkedFrom:) throws StaleEntity for a stale entity and returns the component otherwise")
    func removeChecked() throws {
        var world = World()
        let entity = world.spawn(Health(1))
        let removed = try world.remove(Health.self, checkedFrom: entity)
        let expected = Health(1)
        #expect(removed == expected)
        let again = try world.remove(Health.self, checkedFrom: entity)
        #expect(again == nil)
        world.despawn(entity)
        #expect(throws: StaleEntity()) {
            try world.remove(Health.self, checkedFrom: entity)
        }
    }

    @Test("The checked subscript throws MissingComponent for a missing component or a stale entity")
    func subscriptChecked() throws {
        var world = World()
        let entity = world.spawn(Health(1))
        let expected = Health(1)
        #expect(try world[checked: Health.self, of: entity] == expected)
        #expect(throws: MissingComponent()) {
            try world[checked: Name.self, of: entity]
        }
        world.despawn(entity)
        #expect(throws: MissingComponent()) {
            try world[checked: Health.self, of: entity]
        }
        #expect((try? world[checked: Health.self, of: entity]) == nil)
    }

    @Test("The checked resource subscript throws MissingResource when there is none")
    func resourceChecked() throws {
        var resources = Resources()
        #expect(throws: MissingResource()) {
            try resources[checked: Clock.self]
        }
        resources.insert(Clock(ticks: 3))
        let expected = Clock(ticks: 3)
        #expect(try resources[checked: Clock.self] == expected)
    }
}

extension CheckedTests {
    @Test("The checked spellings throw StaleEntity for an entity the world never spawned, and change nothing")
    func neverSpawned() {
        var world = World()
        let live = world.spawn(Health(1))
        let foreign = Entity(index: 7, generation: 0)
        #expect(throws: StaleEntity()) { try world.despawn(checked: foreign) }
        #expect(throws: StaleEntity()) { try world.insert(Health(2), checkedInto: foreign) }
        #expect(throws: StaleEntity()) { try world.remove(Health.self, checkedFrom: foreign) }
        #expect(throws: MissingComponent()) { try world[checked: Health.self, of: foreign] }
        let count: Int = 1
        #expect(world.count == count)
        #expect(world.count(of: Health.self) == count)
        let health = Health(1)
        #expect(world[Health.self, of: live] == health)
    }

    @Test("remove(_:checkedFrom:) on a stale entity leaves every other entity's component in place")
    func removeCheckedStaleChangesNothing() {
        var world = World()
        let stale = world.spawn(Health(1))
        let kept = world.spawn(Health(2))
        world.despawn(stale)
        #expect(throws: StaleEntity()) { try world.remove(Health.self, checkedFrom: stale) }
        let health = Health(2)
        #expect(world[Health.self, of: kept] == health)
        let count: Int = 1
        #expect(world.count(of: Health.self) == count)
    }
}
