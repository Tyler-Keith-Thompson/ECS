// Each test is self-contained: it builds its own worlds and states its own expectations.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("Groups")
struct GroupTests {
    @Test("A query of grouped types lists the entities holding all of them, in either order of types")
    func query() {
        var world = World()
        let both = world.spawn(Position(x: 1, y: 0), Velocity(dx: 2, dy: 0))
        world.spawn(Position(x: 3, y: 0))
        let late = world.spawn(Velocity(dx: 4, dy: 0))
        world.group(Position.self, Velocity.self)
        world.insert(Position(x: 5, y: 0), into: late)
        let rows = world.query(Position.self, Velocity.self).map { "\($0.entity) \($0.1.x) \($0.2.dx)" }.sorted()
        let reversed = world.query(Velocity.self, Position.self).map { "\($0.entity) \($0.2.x) \($0.1.dx)" }.sorted()
        let expected = ["\(both) 1.0 2.0", "\(late) 5.0 4.0"].sorted()
        #expect(rows == expected)
        #expect(reversed == expected)
    }

    @Test("Updates over exactly the grouped types change every entity holding them")
    func updates() {
        var world = World()
        for value in 0 ..< 100 {
            let entity = world.spawn(Position(x: 0, y: 0))
            if value.isMultiple(of: 3) { world.insert(Velocity(dx: 1, dy: 1), into: entity) }
        }
        world.group(Velocity.self, Position.self)
        world.update(Position.self, reading: Velocity.self) { position, row in position.x += row.components.dx }
        world.update(Position.self, Velocity.self) { position, velocity, _ in
            position.y += 1
            velocity.dy += 1
        }
        world.parallelUpdate(Position.self, reading: Velocity.self, minimumChunk: 5) { position, row in position.y += row.components.dy }
        let moved = world.query(Position.self).filter { $0.1.x == 1 && $0.1.y == 3 }.count
        let still = world.query(Position.self).filter { $0.1 == Position(x: 0, y: 0) }.count
        #expect(moved == 34)
        #expect(still == 66)
    }

    @Test("A three-type group and a second, disjoint group work side by side")
    func threeTypes() {
        var world = World()
        world.group(First.self, Second.self, Third.self)
        world.group(Health.self, Name.self)
        for value in 0 ..< 50 {
            let entity = world.spawn(First(value), Second(value))
            if value.isMultiple(of: 2) { world.insert(Third(value), into: entity) }
            if value.isMultiple(of: 5) { world.insert(Health(value), Name("\(value)"), into: entity) }
        }
        let three = world.query(First.self, Second.self, Third.self).count
        let two = world.query(Health.self, Name.self).count
        let partial = world.query(First.self, Second.self).count
        #expect(three == 25)
        #expect(two == 10)
        #expect(partial == 50)
    }

    @Test("A copy of a world keeps its group, and grouping a copy leaves the original's storage order alone")
    func copies() {
        var world = World()
        for value in 0 ..< 20 {
            let entity = world.spawn(Position(x: Double(value), y: 0))
            if value.isMultiple(of: 4) { world.insert(Velocity(dx: 0, dy: 0), into: entity) }
        }
        let before = world.query(Position.self).map(\.entity)
        var grouped = world
        grouped.group(Position.self, Velocity.self)
        let after = world.query(Position.self).map(\.entity)
        var copy = grouped
        copy.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: 0))
        #expect(after == before)
        #expect(throws: GroupError.alreadyOwned) { try copy.group(checked: Velocity.self, Health.self) }
        #expect(copy.query(Position.self, Velocity.self).count == 6)
    }

    @Test("The checked spelling throws for fewer than two types, a repeated type and an owned type")
    func checked() throws {
        var world = World()
        #expect(throws: GroupError.tooFewTypes) { try world.group(checked: Health.self) }
        #expect(throws: GroupError.tooFewTypes) { try world.group(checked: Health.self, Health.self) }
        try world.group(checked: Health.self, Name.self)
        #expect(throws: GroupError.alreadyOwned) { try world.group(checked: Name.self, Frozen.self) }
    }

    @Test("Grouped and ungrouped worlds agree through any sequence of operations", .tags(.randomized))
    func agreesWithUngrouped() async {
        let operations = Gen.int(in: 0 ... 1_000_000).array(of: 0 ... 300)
        await propertyCheck(count: 200, input: operations) { operations in
            Self.run(operations)
        }
    }

    @Test("Grouped and ungrouped worlds agree through long seeded sequences", .tags(.randomized), arguments: [1, 2, 3, 42, 1_000] as [UInt])
    func seeded(seed: UInt) {
        var generator = SeededRandomNumberGenerator(seed: seed)
        let operations = (0 ..< 3_000).map { _ in Int.random(in: 0 ... 1_000_000, using: &generator) }
        Self.run(operations)
    }

    static func run(_ operations: [Int]) {
        var grouped = World()
        grouped.group(First.self, Second.self)
        var plain = World()
        var live: [Entity] = []
        for code in operations {
            let argument = code / 8
            let target = live.isEmpty ? nil : live[argument % live.count]
            switch (code % 8, target) {
            case (0, _), (_, nil):
                let entity = grouped.spawn(First(argument))
                #expect(plain.spawn(First(argument)) == entity)
                live.append(entity)
            case let (1, entity?):
                grouped.insert(Second(argument), into: entity)
                plain.insert(Second(argument), into: entity)
            case let (2, entity?):
                grouped.insert(First(argument), Second(argument), into: entity)
                plain.insert(First(argument), Second(argument), into: entity)
            case let (3, entity?):
                grouped.remove(First.self, from: entity)
                plain.remove(First.self, from: entity)
            case let (4, entity?):
                grouped.remove(Second.self, from: entity)
                plain.remove(Second.self, from: entity)
            case (5, _):
                grouped.update(First.self, reading: Second.self) { first, row in first.value &+= row.components.value }
                plain.update(First.self, reading: Second.self) { first, row in first.value &+= row.components.value }
            case (6, _):
                grouped.update(First.self, Second.self) { first, second, _ in swap(&first.value, &second.value) }
                plain.update(First.self, Second.self) { first, second, _ in swap(&first.value, &second.value) }
            default:
                grouped.despawn(target!)
                plain.despawn(target!)
                live.removeAll { !grouped.contains($0) }
            }
        }
        #expect(grouped.snapshot(First.self, Second.self) == plain.snapshot(First.self, Second.self))
        let groupedRows = grouped.query(First.self, Second.self).map { "\($0.entity) \($0.1.value) \($0.2.value)" }.sorted()
        let plainRows = plain.query(First.self, Second.self).map { "\($0.entity) \($0.1.value) \($0.2.value)" }.sorted()
        #expect(groupedRows == plainRows)
    }
}
