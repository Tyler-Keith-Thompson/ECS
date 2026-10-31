// Queries and updates of one to three types have specialized overloads; any number of types goes
// through a parameter pack. These tests pin both paths to the same answers. Each is self-contained.

import ECSTestSupport
import Testing
import WorldModule

/// A fourth integer component, so a query can exceed the specialized arities.
struct Fourth: Component, Hashable {
    var value: Int
}

@Suite("Specialized and pack spellings agree")
struct OverloadAgreementTests {
    @Test("Queries of one to four types list the same entities as filters requiring those types", .tags(.randomized), arguments: [7, 99, 2_024] as [UInt])
    func queries(seed: UInt) {
        var generator = SeededRandomNumberGenerator(seed: seed)
        var world = World()
        for value in 0 ..< 400 {
            let entity = world.spawn()
            if Bool.random(using: &generator) { world.insert(First(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Second(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Third(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Fourth(value: value), into: entity) }
            if Int.random(in: 0 ..< 5, using: &generator) == 0 { world.despawn(entity) }
        }
        let one = Set(world.query(First.self).map(\.entity))
        let two = Set(world.query(First.self, Second.self).map(\.entity))
        let three = Set(world.query(First.self, Second.self, Third.self).map(\.entity))
        let four = Set(world.query(First.self, Second.self, Third.self, Fourth.self).map(\.entity))
        #expect(one == Set(Array(world.query().with(First.self))))
        #expect(two == Set(Array(world.query().with(First.self, Second.self))))
        #expect(three == Set(Array(world.query().with(First.self, Second.self, Third.self))))
        #expect(four == Set(Array(world.query().with(First.self, Second.self, Third.self, Fourth.self))))
        for (_, first, second, third, fourth) in world.query(First.self, Second.self, Third.self, Fourth.self) {
            #expect(first.value == second.value)
            #expect(third.value == fourth.value)
            #expect(first.value == third.value)
        }
        for (_, third, first, second) in world.query(Third.self, First.self, Second.self) {
            #expect(third.value == first.value)
            #expect(second.value == first.value)
        }
    }

    @Test("Updates reading zero to four types change the same entities as an equivalent query")
    func updates() {
        var world = World()
        for value in 0 ..< 60 {
            let entity = world.spawn(Health(0))
            if value.isMultiple(of: 2) { world.insert(First(1), into: entity) }
            if value.isMultiple(of: 3) { world.insert(Second(10), into: entity) }
            if value.isMultiple(of: 5) { world.insert(Third(100), into: entity) }
            if value.isMultiple(of: 7) { world.insert(Fourth(value: 1_000), into: entity) }
        }
        world.update(Health.self) { health, _ in health.current = 0 }
        world.update(Health.self, reading: First.self) { health, row in health.current += row.components.value }
        world.update(Health.self, reading: First.self, Second.self) { health, row in health.current += row.components.1.value }
        world.update(Health.self, reading: First.self, Second.self, Third.self) { health, row in health.current += row.components.2.value }
        world.update(Health.self, reading: First.self, Second.self, Third.self, Fourth.self) { health, row in
            health.current += row.components.3.value
        }
        for row in world.query(Health.self) {
            let holds = { (type: any Component.Type) -> Bool in
                switch type {
                case is First.Type: world.contains(First.self, in: row.entity)
                case is Second.Type: world.contains(Second.self, in: row.entity)
                case is Third.Type: world.contains(Third.self, in: row.entity)
                default: world.contains(Fourth.self, in: row.entity)
                }
            }
            var expected = 0
            if holds(First.self) { expected += 1 }
            if holds(First.self), holds(Second.self) { expected += 10 }
            if holds(First.self), holds(Second.self), holds(Third.self) { expected += 100 }
            if holds(First.self), holds(Second.self), holds(Third.self), holds(Fourth.self) { expected += 1_000 }
            #expect(row.1.current == expected)
        }
    }

    @Test("Two-type updates reading zero to four types change the same entities as an equivalent query")
    func twoTypeUpdates() {
        var world = World()
        for value in 0 ..< 60 {
            let entity = world.spawn(Health(0), Name(""))
            if value.isMultiple(of: 2) { world.insert(First(1), into: entity) }
            if value.isMultiple(of: 3) { world.insert(Second(1), into: entity) }
            if value.isMultiple(of: 5) { world.insert(Third(1), into: entity) }
            if value.isMultiple(of: 7) { world.insert(Fourth(value: 1), into: entity) }
        }
        world.update(Health.self, Name.self) { health, name, _ in
            health.current += 1
            name.text += "0"
        }
        world.update(Health.self, Name.self, reading: First.self) { health, name, _ in
            health.current += 1
            name.text += "1"
        }
        world.update(Health.self, Name.self, reading: First.self, Second.self) { health, name, _ in
            health.current += 1
            name.text += "2"
        }
        world.update(Health.self, Name.self, reading: First.self, Second.self, Third.self) { health, name, _ in
            health.current += 1
            name.text += "3"
        }
        world.update(Health.self, Name.self, reading: First.self, Second.self, Third.self, Fourth.self) { health, name, _ in
            health.current += 1
            name.text += "4"
        }
        for row in world.query(Health.self, Name.self) {
            let (e, health, name) = row
            var expected = "0"
            if world.contains(First.self, in: e) {
                expected += "1"
                if world.contains(Second.self, in: e) {
                    expected += "2"
                    if world.contains(Third.self, in: e) {
                        expected += "3"
                        if world.contains(Fourth.self, in: e) { expected += "4" }
                    }
                }
            }
            #expect(name.text == expected)
            #expect(health.current == expected.count)
        }
    }

    @Test("Specialized updates honor filters and the walked column, whichever is smallest")
    func smallestColumnDrives() {
        var world = World()
        var expected: Set<Entity> = []
        for value in 0 ..< 100 {
            let entity = world.spawn(Health(0), First(0))
            if value < 3 {
                world.insert(Second(0), into: entity)
                if value != 1 { expected.insert(entity) } else { world.insert(Frozen(), into: entity) }
            }
        }
        var visited: Set<Entity> = []
        world.update(Health.self, reading: First.self, Second.self, where: .without(Frozen.self)) { _, row in
            visited.insert(row.entity)
        }
        #expect(visited == expected)
        var visitedTwo: Set<Entity> = []
        world.update(Health.self, First.self, reading: Second.self, where: .without(Frozen.self)) { _, _, row in
            visitedTwo.insert(row.entity)
        }
        #expect(visitedTwo == expected)
    }
}
