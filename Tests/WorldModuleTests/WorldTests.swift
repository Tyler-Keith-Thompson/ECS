// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import Foundation
import Testing
import WorldModule

@Suite("World: entities and components")
struct WorldTests {
    @Test("A new world has no entities")
    func empty() {
        let world = World()
        let expected: [Entity] = []
        #expect(world.count == 0)
        #expect(world.isEmpty)
        #expect(Array(world.entities) == expected)
    }

    @Test("Spawning hands out slots in order, at generation zero")
    func spawnOrder() {
        var world = World()
        let first = world.spawn()
        let second = world.spawn(Health(3))
        let expectedFirst = Entity(index: 0, generation: 0)
        let expectedSecond = Entity(index: 1, generation: 0)
        #expect(first == expectedFirst)
        #expect(second == expectedSecond)
        #expect(world.count == 2)
        #expect(Array(world.entities) == [first, second])
    }

    @Test("A spawned entity holds the components it was spawned with")
    func spawnComponents() {
        var world = World()
        let ball = world.spawn(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))
        let position = Position(x: 1, y: 2)
        let velocity = Velocity(dx: 3, dy: 4)
        #expect(world[Position.self, of: ball] == position)
        #expect(world[Velocity.self, of: ball] == velocity)
        #expect(world.contains(Position.self, in: ball))
        #expect(!world.contains(Health.self, in: ball))
    }

    @Test("Spawning two components of one type keeps the later")
    func spawnDuplicateType() {
        var world = World()
        let entity = world.spawn(Health(1), Health(2))
        let expected = Health(2)
        #expect(world[Health.self, of: entity] == expected)
        #expect(world.count(of: Health.self) == 1)
    }

    @Test("A despawned entity's handle is stale, and its slot is reused at the next generation")
    func despawnAndReuse() {
        var world = World()
        let first = world.spawn(Health(1))
        world.despawn(first)
        #expect(!world.contains(first))
        #expect(!world.contains(Health.self, in: first))
        #expect(world.count == 0)
        let second = world.spawn(Health(2))
        let expected = Entity(index: 0, generation: 1)
        #expect(second == expected)
        #expect(!world.contains(first))
        #expect(world.contains(second))
    }

    @Test("The most recently vacated slot is reused first")
    func reuseOrder() {
        var world = World()
        let a = world.spawn()
        let b = world.spawn()
        world.despawn(a)
        world.despawn(b)
        let next = world.spawn()
        #expect(next.index == b.index)
        let after = world.spawn()
        #expect(after.index == a.index)
    }

    @Test("Despawning removes every component, and other entities keep theirs")
    func despawnKeepsOthers() {
        var world = World()
        let a = world.spawn(Health(1), Name("a"))
        let b = world.spawn(Health(2), Name("b"))
        let c = world.spawn(Health(3))
        world.despawn(a)
        let healthB = Health(2)
        let healthC = Health(3)
        let nameB = Name("b")
        #expect(world[Health.self, of: b] == healthB)
        #expect(world[Health.self, of: c] == healthC)
        #expect(world[Name.self, of: b] == nameB)
        #expect(world.count(of: Health.self) == 2)
        #expect(world.count(of: Name.self) == 1)
    }

    @Test("Inserting adds a component, and inserting again replaces it")
    func insertReplaces() {
        var world = World()
        let entity = world.spawn()
        world.insert(Health(5), into: entity)
        let five = Health(5)
        #expect(world[Health.self, of: entity] == five)
        world.insert(Health(7), Name("seven"), into: entity)
        let seven = Health(7)
        let name = Name("seven")
        #expect(world[Health.self, of: entity] == seven)
        #expect(world[Name.self, of: entity] == name)
        #expect(world.count(of: Health.self) == 1)
    }

    @Test("Removing returns the component, and removing again returns nil")
    func removeReturns() {
        var world = World()
        let entity = world.spawn(Health(5))
        let removed = world.remove(Health.self, from: entity)
        let expected = Health(5)
        #expect(removed == expected)
        #expect(world.remove(Health.self, from: entity) == nil)
        #expect(!world.contains(Health.self, in: entity))
        #expect(world.contains(entity))
    }

    @Test("Removing from the middle keeps every other entity's component")
    func removeSwapsLast() {
        var world = World()
        let entities = (0 ..< 5).map { world.spawn(Health($0)) }
        world.remove(Health.self, from: entities[1])
        for (value, entity) in entities.enumerated() where value != 1 {
            let expected = Health(value)
            #expect(world[Health.self, of: entity] == expected)
        }
        #expect(world.count(of: Health.self) == 4)
    }

    @Test("Writing through the subscript changes the component in place")
    func subscriptModify() {
        var world = World()
        let hero = world.spawn(Health(10))
        world[Health.self, of: hero].current -= 3
        let expected = Health(7)
        #expect(world[Health.self, of: hero] == expected)
    }

    @Test("A copy of a world is independent of the original", .tags(.copyOnWrite))
    func valueSemantics() {
        var original = World()
        let hero = original.spawn(Health(10), Name("hero"))
        var copy = original
        copy[Health.self, of: hero].current = 1
        copy.insert(Position(x: 0, y: 0), into: hero)
        let villain = copy.spawn(Health(99))
        original.remove(Name.self, from: hero)

        let ten = Health(10)
        let one = Health(1)
        let name = Name("hero")
        #expect(original[Health.self, of: hero] == ten)
        #expect(copy[Health.self, of: hero] == one)
        #expect(!original.contains(Position.self, in: hero))
        #expect(!original.contains(villain))
        #expect(copy[Name.self, of: hero] == name)
        #expect(original.count == 1)
        #expect(copy.count == 2)
    }

    @Test("Despawning in a copy leaves the original's entity live", .tags(.copyOnWrite))
    func despawnCopy() {
        var original = World()
        let hero = original.spawn(Health(10))
        var copy = original
        copy.despawn(hero)
        let ten = Health(10)
        #expect(original.contains(hero))
        #expect(original[Health.self, of: hero] == ten)
        #expect(!copy.contains(hero))
    }

    @Test("An entity from another world's slot is stale here when its generation differs")
    func foreignGeneration() {
        var world = World()
        _ = world.spawn()
        let forged = Entity(index: 0, generation: 5)
        let outOfRange = Entity(index: 9, generation: 0)
        #expect(!world.contains(forged))
        #expect(!world.contains(outOfRange))
        #expect(!world.contains(Health.self, in: outOfRange))
    }

    @Test("Entities order by slot, then generation, and describe themselves as index:generation", .tags(.conformance))
    func entityOrder() {
        let a = Entity(index: 1, generation: 9)
        let b = Entity(index: 2, generation: 0)
        let c = Entity(index: 2, generation: 1)
        #expect(a < b)
        #expect(b < c)
        #expect(c.description == "2:1")
    }

    @Test("An entity round-trips through Codable", .tags(.conformance))
    func entityCodable() throws {
        let entity = Entity(index: 4, generation: 2)
        let data = try JSONEncoder().encode(entity)
        let decoded = try JSONDecoder().decode(Entity.self, from: data)
        #expect(decoded == entity)
    }

    @Test("A marker component with no stored properties can be inserted and queried")
    func markerComponent() {
        var world = World()
        let entity = world.spawn(Frozen())
        #expect(world.contains(Frozen.self, in: entity))
        #expect(world.count(of: Frozen.self) == 1)
    }
}
