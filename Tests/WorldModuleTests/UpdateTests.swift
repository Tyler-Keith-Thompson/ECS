// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import Testing
import WorldModule

@Suite("World: in-place updates")
struct UpdateTests {
    @Test("update changes every component of the type")
    func updateAll() {
        var world = World()
        let entities = (1 ... 3).map { world.spawn(Health($0)) }
        world.update(Health.self) { health, _ in health.current *= 10 }
        let values = entities.map { world[Health.self, of: $0].current }
        #expect(values == [10, 20, 30])
    }

    @Test("update passes each entity's handle in the row")
    func updatePassesEntity() {
        var world = World()
        let entities = (0 ..< 3).map { _ in world.spawn(Name("")) }
        world.update(Name.self) { name, row in name.text = row.entity.description }
        for entity in entities {
            #expect(world[Name.self, of: entity].text == entity.description)
        }
    }

    @Test("update visits only entities holding every read type, and passes their components")
    func updateReading() {
        var world = World()
        let moving = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
        let still = world.spawn(Position(x: 5, y: 5))
        world.update(Position.self, reading: Velocity.self) { position, row in
            position.x += row.components.dx
            position.y += row.components.dy
        }
        let moved = Position(x: 1, y: 2)
        let unmoved = Position(x: 5, y: 5)
        #expect(world[Position.self, of: moving] == moved)
        #expect(world[Position.self, of: still] == unmoved)
    }

    @Test("update reading several types drives from the smallest and visits the intersection")
    func updateReadingSeveral() {
        var world = World()
        var expected: [Entity: Int] = [:]
        for value in 0 ..< 20 {
            let entity = world.spawn(Health(0))
            if value.isMultiple(of: 2) { world.insert(First(value), into: entity) }
            if value.isMultiple(of: 5) { world.insert(Second(1), into: entity) }
            expected[entity] = value.isMultiple(of: 10) ? value + 1 : 0
        }
        world.update(Health.self, reading: First.self, Second.self) { health, row in
            let (first, second) = row.components
            health.current = first.value + second.value
        }
        for (entity, value) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(world[Health.self, of: entity].current == value)
        }
    }

    @Test("update respects its filter")
    func updateFilter() {
        var world = World()
        let frozen = world.spawn(Health(1), Frozen())
        let free = world.spawn(Health(1))
        world.update(Health.self, where: .without(Frozen.self)) { health, _ in health.current = 9 }
        #expect(world[Health.self, of: frozen].current == 1)
        #expect(world[Health.self, of: free].current == 9)
        world.update(Health.self, where: .with(Frozen.self)) { health, _ in health.current = 7 }
        #expect(world[Health.self, of: frozen].current == 7)
        #expect(world[Health.self, of: free].current == 9)
    }

    @Test("update of a type the world never stored, or with an unsatisfiable filter, visits nothing")
    func updateNothing() {
        var world = World()
        _ = world.spawn(Health(1))
        var visits = 0
        world.update(Name.self) { _, _ in visits += 1 }
        world.update(Health.self, reading: Name.self) { _, _ in visits += 1 }
        world.update(Health.self, where: .with(Name.self)) { _, _ in visits += 1 }
        #expect(visits == 0)
    }

    @Test("update on a copy leaves the original alone", .tags(.copyOnWrite))
    func updateCopy() {
        var original = World()
        let entity = original.spawn(Health(1))
        var copy = original
        copy.update(Health.self) { health, _ in health.current = 2 }
        #expect(original[Health.self, of: entity].current == 1)
        #expect(copy[Health.self, of: entity].current == 2)
    }

    @Test("A throwing update stops at the error and keeps the changes made before it")
    func updateThrows() {
        struct Stop: Error, Equatable {}
        var world = World()
        let entities = (0 ..< 4).map { world.spawn(Health($0)) }
        #expect(throws: Stop()) {
            try world.update(Health.self) { (health, _) throws(Stop) in
                if health.current == 2 { throw Stop() }
                health.current += 10
            }
        }
        let values = entities.map { world[Health.self, of: $0].current }
        #expect(values == [10, 11, 2, 3])
        world[Health.self, of: entities[3]].current = 0
        #expect(world.count(of: Health.self) == 4)
    }

    @Test("Two-type update changes both components of entities holding both")
    func updateTwo() {
        var world = World()
        let both = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1), Health(2))
        let positionOnly = world.spawn(Position(x: 0, y: 0), Health(2))
        world.update(Position.self, Velocity.self, reading: Health.self) { position, velocity, row in
            position.x += velocity.dx * Double(row.components.current)
            velocity.dx = 0
        }
        let moved = Position(x: 2, y: 0)
        let stopped = Velocity(dx: 0, dy: 1)
        let unmoved = Position(x: 0, y: 0)
        #expect(world[Position.self, of: both] == moved)
        #expect(world[Velocity.self, of: both] == stopped)
        #expect(world[Position.self, of: positionOnly] == unmoved)
    }

    @Test("Two-type update driven by either written type visits the same entities")
    func updateTwoDriver() {
        var world = World()
        var expected: Set<Entity> = []
        for value in 0 ..< 12 {
            let entity = world.spawn(First(0))
            if value.isMultiple(of: 3) {
                world.insert(Second(0), into: entity)
                expected.insert(entity)
            }
        }
        var visitedFirstDriven: Set<Entity> = []
        world.update(First.self, Second.self) { _, _, row in visitedFirstDriven.insert(row.entity) }
        var visitedSecondDriven: Set<Entity> = []
        world.update(Second.self, First.self) { _, _, row in visitedSecondDriven.insert(row.entity) }
        #expect(visitedFirstDriven == expected)
        #expect(visitedSecondDriven == expected)
    }

    @Test("Two-type update respects its filter")
    func updateTwoFilter() {
        var world = World()
        let frozen = world.spawn(First(0), Second(0), Frozen())
        let free = world.spawn(First(0), Second(0))
        world.update(First.self, Second.self, where: .without(Frozen.self)) { first, second, _ in
            first.value = 1
            second.value = 1
        }
        #expect(world[First.self, of: frozen].value == 0)
        #expect(world[Second.self, of: free].value == 1)
    }

    @Test("A throwing two-type update, or update over a query, stops at the error and keeps the changes made before it")
    func updateThrowsOtherSpellings() {
        struct Stop: Error, Equatable {}
        var world = World()
        let entities = (0 ..< 4).map { world.spawn(First($0), Second($0), Health($0)) }
        #expect(throws: Stop()) {
            try world.update(First.self, Second.self) { (first, second, _) throws(Stop) in
                if first.value == 2 { throw Stop() }
                first.value += 10
                second.value += 10
            }
        }
        #expect(throws: Stop()) {
            try world.update(Health.self, over: Query(First.self)) { (health, row) throws(Stop) in
                if health.current == 1 { throw Stop() }
                health.current = row.components.value
            }
        }
        let firsts: [Int] = entities.map { world[First.self, of: $0].value }
        let seconds: [Int] = entities.map { world[Second.self, of: $0].value }
        let healths: [Int] = entities.map { world[Health.self, of: $0].current }
        let expectedFirsts: [Int] = [10, 11, 2, 3]
        let expectedHealths: [Int] = [10, 1, 2, 3]
        #expect(firsts == expectedFirsts)
        #expect(seconds == expectedFirsts)
        #expect(healths == expectedHealths)
    }

    @Test("An update marks every component it visits changed, even one its body leaves as it was")
    func marksUnchangedBody() {
        var world = World()
        let moving = world.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: 0))
        let still = world.spawn(Position(x: 0, y: 0))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world.update(Position.self, reading: Velocity.self) { _, _ in }
        world.update(Velocity.self, over: Query(AnyOf<Position, Health>.self)) { _, _ in }
        let position: [Entity] = Array(world.query().changed(Position.self, since: checkpoint))
        let velocity: [Entity] = Array(world.query().changed(Velocity.self, since: checkpoint))
        let expected: [Entity] = [moving]
        #expect(position == expected)
        #expect(velocity == expected)
        #expect(world.contains(still))
    }

    @Test("An update visits entities in the storage order of the type the fewest entities hold")
    func visitOrder() {
        var world = World()
        let a = world.spawn(Position(x: 0, y: 0), Health(0))
        _ = world.spawn(Position(x: 0, y: 0), Health(0))
        let c = world.spawn(Position(x: 0, y: 0), Health(0))
        world.insert(Velocity(dx: 0, dy: 0), into: c)
        world.insert(Velocity(dx: 0, dy: 0), into: a)
        var reading: [Entity] = []
        world.update(Position.self, reading: Velocity.self) { _, row in reading.append(row.entity) }
        var writing: [Entity] = []
        world.update(Position.self, Velocity.self) { _, _, row in writing.append(row.entity) }
        var filtered: [Entity] = []
        world.update(Health.self, where: .with(Velocity.self)) { _, row in filtered.append(row.entity) }
        var three: [Entity] = []
        world.update(Position.self, Health.self, Velocity.self, over: Query()) { _, _, _, row in three.append(row.entity) }
        let expected: [Entity] = [c, a]
        #expect(reading == expected)
        #expect(writing == expected)
        #expect(filtered == expected)
        #expect(three == expected)
    }

    @Test("A two-type update over a query that reads a written type traps", .tags(.precondition))
    func twoOverReadsWritten() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: 0))
            world.update(Position.self, Velocity.self, over: Query(AnyOf<Health, Velocity>.self)) { _, _, _ in }
        }
    }

    @Test("A two-type update over a query that writes one type twice traps", .tags(.precondition))
    func twoOverWritesTwice() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.spawn(Position(x: 0, y: 0), Health(1))
            world.update(Position.self, Position.self, over: Query(Health.self)) { _, _, _ in }
        }
    }

    @Test("A three-type update over a query that reads a written type traps", .tags(.precondition))
    func threeOverReadsWritten() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: 0), Health(1))
            world.update(Position.self, Velocity.self, Health.self, over: Query(Health.self)) { _, _, _, _ in }
        }
    }
}
