// Queries as values: terms, AnyOf groups, filters (anyOf among them) and updates over a query.
// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("World: query values")
struct QueryValueTests {
    @Test("A query of components visits the same rows as the type-listing spelling")
    func componentsAgree() {
        var world = World()
        let both = world.spawn(Position(x: 1, y: 1), Velocity(dx: 1, dy: 0))
        _ = world.spawn(Position(x: 2, y: 2))
        let alsoBoth = world.spawn(Velocity(dx: 4, dy: 0), Position(x: 4, y: 4))
        let query = Query(Position.self, Velocity.self)
        let rows = world.query(query).map(\.entity).sorted()
        let listed = world.query(Position.self, Velocity.self).map(\.entity).sorted()
        let expected = [both, alsoBoth]
        #expect(rows == expected)
        #expect(listed == expected)
    }

    @Test("AnyOf matches entities holding at least one of its types and yields each as an optional")
    func anyOfYieldsOptionals() {
        var world = World()
        let onlySecond = world.spawn(First(1), Second(20))
        let onlyThird = world.spawn(First(2), Third(300))
        let both = world.spawn(First(3), Second(40), Third(500))
        _ = world.spawn(First(4))
        _ = world.spawn(Second(60))
        var seen: [Entity: String] = [:]
        for (entity, first, (second, third)) in world.query(Query(First.self, AnyOf<Second, Third>.self)) {
            seen[entity] = "\(first.value) \(second?.value ?? -1) \(third?.value ?? -1)"
        }
        let expected: [Entity: String] = [onlySecond: "1 20 -1", onlyThird: "2 -1 300", both: "3 40 500"]
        #expect(seen == expected)
    }

    @Test("A query of only an AnyOf visits every entity holding one of its types")
    func anyOfAlone() {
        var world = World()
        let second = world.spawn(Second(1))
        let third = world.spawn(Third(2))
        _ = world.spawn(First(3))
        _ = world.spawn()
        let rows = world.query(Query(AnyOf<Second, Third>.self)).map(\.entity).sorted()
        let expected = [second, third]
        #expect(rows == expected)
    }

    @Test("Several AnyOf groups must each be met")
    func anyOfGroupsAnd() {
        var world = World()
        let match = world.spawn(First(1), Third(2))
        _ = world.spawn(First(1))
        _ = world.spawn(Third(2))
        let alsoMatch = world.spawn(Second(1), Position(x: 0, y: 0))
        let query = Query(AnyOf<First, Second>.self, AnyOf<Third, Position, Velocity>.self)
        let rows = world.query(query).map(\.entity).sorted()
        let expected = [match, alsoMatch]
        #expect(rows == expected)
    }

    @Test("AnyOf groups of two, three and four types yield one optional per type, in order")
    func anyOfSizes() throws {
        var world = World()
        let entity = world.spawn(Second(2), Health(4))
        let two = try #require(world.query(Query(AnyOf<First, Second>.self)).first { _ in true })
        let three = try #require(world.query(Query(AnyOf<First, Second, Third>.self)).first { _ in true })
        let four = try #require(world.query(Query(AnyOf<First, Second, Third, Health>.self)).first { _ in true })
        let expectedSecond = Second(2)
        let expectedHealth = Health(4)
        #expect(two.entity == entity)
        #expect(two.1.0 == nil)
        #expect(two.1.1 == expectedSecond)
        #expect(three.1.2 == nil)
        #expect(four.1.3 == expectedHealth)
    }

    @Test("An empty world has no rows, and a world of one matching entity has one")
    func emptyAndOne() {
        var world = World()
        let query = Query(First.self, AnyOf<Second, Third>.self)
        let emptyCount = world.query(query).count
        let entity = world.spawn(First(1), Third(3))
        let rows = world.query(query).map(\.entity)
        let expectedEmpty = 0
        let expected = [entity]
        #expect(emptyCount == expectedEmpty)
        #expect(rows == expected)
    }

    @Test("Filters on a query narrow its rows")
    func filters() {
        var world = World()
        let kept = world.spawn(First(1), Second(2))
        _ = world.spawn(First(1), Second(2), Frozen())
        _ = world.spawn(First(1))
        let query = Query(First.self).with(Second.self).without(Frozen.self)
        let rows = world.query(query).map(\.entity)
        let expected = [kept]
        #expect(rows == expected)
    }

    @Test("anyOf filters pass entities meeting at least one filter, so OR of ANDs can be written")
    func anyOfFilters() {
        var world = World()
        let firstAndSecond = world.spawn(Health(1), First(1), Second(2))
        _ = world.spawn(Health(2), First(1))
        let third = world.spawn(Health(3), Third(3))
        _ = world.spawn(Health(4), Second(2))
        let notFrozen = world.spawn(Health(5), Second(2), Third(3))
        // (First && Second) || Third, and also not frozen or lacking a Second.
        let query = Query(Health.self)
            .anyOf(.with(First.self, Second.self), .with(Third.self))
            .anyOf(.without(Frozen.self), .without(Second.self))
        _ = world.spawn(Health(6), Third(3), Second(2), Frozen())
        let rows = world.query(query).map(\.entity).sorted()
        let expected = [firstAndSecond, third, notFrozen]
        #expect(rows == expected)
    }

    @Test("anyOf with no filters passes nothing")
    func emptyAnyOf() {
        var world = World()
        _ = world.spawn(First(1))
        let count = world.query(Query(First.self).anyOf()).count
        let entities = world.query().anyOf().count
        let expected = 0
        #expect(count == expected)
        #expect(entities == expected)
    }

    @Test("anyOf filters on views and filter values agree with anyOf on queries")
    func anyOfOnViews() {
        var world = World()
        let first = world.spawn(Health(1), First(1))
        let second = world.spawn(Health(2), Second(2))
        _ = world.spawn(Health(3))
        let viewRows = world.query(Health.self).anyOf(.with(First.self), .with(Second.self)).map(\.entity).sorted()
        let entityRows = world.query().anyOf(.with(First.self), .with(Second.self)).sorted()
        let filtered = world.query(Health.self).filtered(by: .anyOf(.with(First.self), .with(Second.self))).map(\.entity).sorted()
        let queryRows = world.query(Query(Health.self).anyOf(.with(First.self), .with(Second.self))).map(\.entity).sorted()
        let expected = [first, second]
        #expect(viewRows == expected)
        #expect(entityRows == expected)
        #expect(filtered == expected)
        #expect(queryRows == expected)
    }

    @Test("anyOf over a type no entity ever held drops that alternative")
    func anyOfMissingColumn() {
        var world = World()
        let first = world.spawn(First(1))
        let rows = world.query(Query(First.self).anyOf(.with(Second.self), .without(Third.self))).map(\.entity)
        let none = world.query(Query(First.self).anyOf(.with(Second.self), .changed(Third.self))).count
        let expected = [first]
        let expectedNone = 0
        #expect(rows == expected)
        #expect(none == expectedNone)
    }

    @Test("Queries with the same terms and filters are equal; different filters are not")
    func equality() {
        let one = Query(First.self, AnyOf<Second, Third>.self).without(Frozen.self)
        let same = Query(First.self, AnyOf<Second, Third>.self).without(Frozen.self)
        let other = Query(First.self, AnyOf<Second, Third>.self).with(Frozen.self)
        #expect(one == same)
        #expect(one.hashValue == same.hashValue)
        #expect(one != other)
    }

    @Test("An update over a query changes the written type of matching entities, with the row alongside")
    func updateOne() {
        var world = World()
        let wind = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Second(10))
        let current = world.spawn(Position(x: 0, y: 0), Velocity(dx: 2, dy: 0), Third(100))
        let still = world.spawn(Position(x: 0, y: 0), Velocity(dx: 3, dy: 0))
        world.update(Position.self, over: Query(Velocity.self, AnyOf<Second, Third>.self)) { position, row in
            let (velocity, (second, third)) = row.components
            position.x += velocity.dx + Double(second?.value ?? 0) + Double(third?.value ?? 0)
        }
        let expectedWind = 11.0
        let expectedCurrent = 102.0
        let expectedStill = 0.0
        #expect(world[Position.self, of: wind].x == expectedWind)
        #expect(world[Position.self, of: current].x == expectedCurrent)
        #expect(world[Position.self, of: still].x == expectedStill)
    }

    @Test("Updates over a query write two and three types")
    func updateTwoAndThree() {
        var world = World()
        let entity = world.spawn(First(1), Second(2), Third(3), Health(10))
        _ = world.spawn(First(1), Second(2), Third(3))
        world.update(First.self, Second.self, over: Query(Health.self)) { first, second, row in
            first.value += row.components.current
            second.value += row.components.current
        }
        world.update(First.self, Second.self, Third.self, over: Query(AnyOf<Health, Name>.self)) { first, second, third, row in
            let (health, _) = row.components
            first.value += health?.current ?? 0
            second.value += 1
            third.value += 1
        }
        let expectedFirst = 21
        let expectedSecond = 13
        let expectedThird = 4
        #expect(world[First.self, of: entity].value == expectedFirst)
        #expect(world[Second.self, of: entity].value == expectedSecond)
        #expect(world[Third.self, of: entity].value == expectedThird)
    }

    @Test("An update over a query marks each written component changed")
    func updateMarksChanged() {
        var world = World()
        let touched = world.spawn(First(1), Second(2))
        _ = world.spawn(First(1))
        let before = world.changeTick
        world.advanceChangeTick()
        world.update(First.self, over: Query(AnyOf<Second, Third>.self)) { first, _ in first.value += 1 }
        let changed = world.query(First.self).changed(First.self, since: before).map(\.entity)
        let expected = [touched]
        #expect(changed == expected)
    }

    @Test("An update over an owning group's types still checks AnyOf terms per entity")
    func groupedAnyOf() {
        var world = World()
        world.group(Position.self, Velocity.self)
        let named = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Name("a"))
        let bare = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let ungrouped = world.spawn(Position(x: 0, y: 0), Health(1))
        world.update(Position.self, over: Query(Velocity.self, AnyOf<Health, Name>.self)) { position, row in
            position.x += row.components.0.dx
        }
        let rows = world.query(Query(Position.self, Velocity.self, AnyOf<Health, Name>.self)).map(\.entity)
        let expectedNamed = 1.0
        let expectedOthers = 0.0
        let expectedRows = [named]
        #expect(world[Position.self, of: named].x == expectedNamed)
        #expect(world[Position.self, of: bare].x == expectedOthers)
        #expect(world[Position.self, of: ungrouped].x == expectedOthers)
        #expect(rows == expectedRows)
    }

    @Test("Queries wider than the specialized overloads read the same rows", .tags(.randomized), arguments: [1, 2, 3, 42, 1_000] as [UInt])
    func wideQueries(seed: UInt) {
        var generator = SeededRandomNumberGenerator(seed: seed)
        var world = World()
        for value in 0 ..< 300 {
            let entity = world.spawn(Health(value))
            if Bool.random(using: &generator) { world.insert(First(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Second(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Third(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Name("\(value)"), into: entity) }
        }
        var wide: [Entity: String] = [:]
        for (entity, health, first, (second, third), (name, _)) in world.query(Query(Health.self, First.self, AnyOf<Second, Third>.self, AnyOf<Name, Frozen>.self)) {
            wide[entity] = "\(health.current) \(first.value) \(second?.value ?? -1) \(third?.value ?? -1) \(name?.text ?? "")"
        }
        var narrow: [Entity: String] = [:]
        for (entity, health, first, (second, third)) in world.query(Query(Health.self, First.self, AnyOf<Second, Third>.self)) {
            guard world.contains(Name.self, in: entity) else { continue }
            let name = world[Name.self, of: entity]
            narrow[entity] = "\(health.current) \(first.value) \(second?.value ?? -1) \(third?.value ?? -1) \(name.text)"
        }
        var fiveWide = 0
        for (_, _, (_, _, _, _, _)) in world.query(Query(Health.self, AnyOf<First, Second, Third, Name, Frozen>.self)) {
            fiveWide += 1
        }
        let expectedFiveWide = world.query(Health.self).filter { row in
            world.contains(First.self, in: row.entity) || world.contains(Second.self, in: row.entity)
                || world.contains(Third.self, in: row.entity) || world.contains(Name.self, in: row.entity)
        }.count
        #expect(wide == narrow)
        #expect(fiveWide == expectedFiveWide)
    }

    @Test("The general path of a query agrees with every specialized shape", .tags(.randomized), arguments: [1, 2, 3, 42, 1_000] as [UInt])
    func generalAgreesWithSpecialized(seed: UInt) {
        // Closures rather than `\.entity`: a key path into a row whose pack is generic crashes the
        // Swift runtime (KNOWN_ISSUES.md).
        func general<each T: QueryTerm>(_ query: Query<repeat each T>, in world: World) -> [Entity] {
            world.query(query).map { $0.entity }.sorted()
        }
        var generator = SeededRandomNumberGenerator(seed: seed)
        var world = World()
        for value in 0 ..< 300 {
            let entity = world.spawn()
            if Bool.random(using: &generator) { world.insert(First(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Second(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Third(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Health(value), into: entity) }
        }
        let one = Query(AnyOf<First, Second>.self)
        let two = Query(First.self, AnyOf<Second, Third, Health>.self)
        let three = Query(AnyOf<First, Second>.self, Third.self, AnyOf<First, Second, Third, Health>.self)
        let specializedOne = world.query(one).map(\.entity).sorted()
        let specializedTwo = world.query(two).map(\.entity).sorted()
        let specializedThree = world.query(three).map(\.entity).sorted()
        #expect(general(one, in: world) == specializedOne)
        #expect(general(two, in: world) == specializedTwo)
        #expect(general(three, in: world) == specializedThree)
    }

    @Test("A query is equal to the same query bound to a world, and hashes the same")
    func boundEquality() {
        var world = World()
        world.spawn(Position(x: 0, y: 0))
        let query = Query(Position.self).without(Frozen.self)
        let bound = query._bound(to: world.query(query))
        #expect(bound == query)
        #expect(bound.hashValue == query.hashValue)
    }

    @Test("filtered(by:) on a query keeps its own conditions and adds the filter's")
    func queryFilteredBy() {
        var world = World()
        let kept = world.spawn(First(1), Second(2))
        _ = world.spawn(First(1), Second(2), Frozen())
        _ = world.spawn(First(1))
        let query = Query(First.self).without(Frozen.self).filtered(by: .with(Second.self))
        let rows = world.query(query).map { $0.entity }
        let expected = [kept]
        #expect(rows == expected)
    }

    @Test("A query reading a disabling component through AnyOf visits the entities holding it, as an update over it does")
    func anyOfReadsDisabling() {
        var world = World()
        let disabled = world.spawn(Position(x: 0, y: 0), Disabled())
        let frozen = world.spawn(Position(x: 0, y: 0), Frozen())
        _ = world.spawn(Position(x: 0, y: 0))
        let query = Query(Position.self, AnyOf<Disabled, Frozen>.self)
        let rows: [Entity] = world.query(query).map { $0.entity }.sorted()
        let general: [Entity] = world.query(Query(Position.self, AnyOf<Disabled, Frozen>.self, AnyOf<First, Position>.self)).map { $0.entity }.sorted()
        var updated: [Entity] = []
        world.update(Position.self, over: Query(AnyOf<Disabled, Frozen>.self)) { _, row in updated.append(row.entity) }
        let expected: [Entity] = [disabled, frozen].sorted()
        #expect(rows == expected)
        #expect(general == expected)
        #expect(updated.sorted() == expected)
    }

    @Test("The general path of an update over a query agrees with every specialized shape", .tags(.randomized), arguments: [1, 2, 3, 42, 1_000] as [UInt])
    func generalUpdateAgreesWithSpecialized(seed: UInt) {
        func general<each T: QueryTerm>(_ query: Query<repeat each T>, in world: inout World) -> [Entity] {
            var visited: [Entity] = []
            world.update(Health.self, over: query) { health, row in
                health.current += 1
                visited.append(row.entity)
            }
            return visited.sorted()
        }
        var generator = SeededRandomNumberGenerator(seed: seed)
        var world = World()
        for value in 0 ..< 300 {
            let entity = world.spawn()
            if Bool.random(using: &generator) { world.insert(First(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Second(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Third(value), into: entity) }
            if Bool.random(using: &generator) { world.insert(Health(0), into: entity) }
        }
        var specialized = world
        var visitedOne: [Entity] = []
        var visitedTwo: [Entity] = []
        var visitedThree: [Entity] = []
        specialized.update(Health.self, over: Query(AnyOf<First, Second>.self)) { health, row in
            health.current += 1
            visitedOne.append(row.entity)
        }
        specialized.update(Health.self, over: Query(First.self, AnyOf<Second, Third>.self)) { health, row in
            health.current += 1
            visitedTwo.append(row.entity)
        }
        specialized.update(Health.self, over: Query(AnyOf<First, Second>.self, Third.self, AnyOf<First, Second, Third>.self).without(Frozen.self)) { health, row in
            health.current += 1
            visitedThree.append(row.entity)
        }
        #expect(general(Query(AnyOf<First, Second>.self), in: &world) == visitedOne.sorted())
        #expect(general(Query(First.self, AnyOf<Second, Third>.self), in: &world) == visitedTwo.sorted())
        #expect(general(Query(AnyOf<First, Second>.self, Third.self, AnyOf<First, Second, Third>.self).without(Frozen.self), in: &world) == visitedThree.sorted())
        #expect(world.snapshot(Health.self) == specialized.snapshot(Health.self))
    }

    @Test("A query with AnyOf and filters agrees with a dictionary model", .tags(.randomized))
    func agreesWithModel() async {
        let worlds = Gen.int(in: 0 ... 31).array(of: 0 ... 200)
        await propertyCheck(count: 200, input: worlds) { masks in
            var world = World()
            var expected: [Entity: String] = [:]
            for (value, mask) in masks.enumerated() {
                let entity = world.spawn()
                if mask & 1 != 0 { world.insert(First(value), into: entity) }
                if mask & 2 != 0 { world.insert(Second(value), into: entity) }
                if mask & 4 != 0 { world.insert(Third(value), into: entity) }
                if mask & 8 != 0 { world.insert(Frozen(), into: entity) }
                if mask & 16 != 0 { world.insert(Health(value), into: entity) }
                let matches = mask & 1 != 0 && mask & 6 != 0 && (mask & 8 == 0 || mask & 16 != 0)
                if matches {
                    let second = mask & 2 != 0 ? value : -1
                    let third = mask & 4 != 0 ? value : -1
                    expected[entity] = "\(value) \(second) \(third)"
                }
            }
            var actual: [Entity: String] = [:]
            let query = Query(First.self, AnyOf<Second, Third>.self).anyOf(.without(Frozen.self), .with(Health.self))
            for (entity, first, (second, third)) in world.query(query) {
                actual[entity] = "\(first.value) \(second?.value ?? -1) \(third?.value ?? -1)"
            }
            #expect(actual == expected)
        }
    }
}
