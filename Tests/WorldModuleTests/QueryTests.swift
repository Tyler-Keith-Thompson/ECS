// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

/// A relation for the tests of filter spellings.
struct Guards: Relation, Hashable {}

@Suite("World: queries")
struct QueryTests {
    @Test("A query lists exactly the entities holding every queried type")
    func intersection() {
        var world = World()
        let both = world.spawn(Position(x: 1, y: 1), Velocity(dx: 1, dy: 0))
        _ = world.spawn(Position(x: 2, y: 2))
        _ = world.spawn(Velocity(dx: 3, dy: 0))
        let alsoBoth = world.spawn(Velocity(dx: 4, dy: 0), Position(x: 4, y: 4))
        let rows = world.query(Position.self, Velocity.self).map(\.entity).sorted()
        #expect(rows == [both, alsoBoth])
    }

    @Test("A row is the entity, then its components in the order the query listed their types")
    func componentOrder() throws {
        var world = World()
        let spawned = world.spawn(Velocity(dx: 3, dy: 4), Position(x: 1, y: 2))
        let row = try #require(world.query(Position.self, Velocity.self).first { _ in true })
        let (entity, position, velocity) = row
        let expectedPosition = Position(x: 1, y: 2)
        let expectedVelocity = Velocity(dx: 3, dy: 4)
        #expect(entity == spawned)
        #expect(row.entity == spawned)
        #expect(position == expectedPosition)
        #expect(velocity == expectedVelocity)
    }

    @Test("A loop can destructure every row of one, two and three types")
    func destructuring() {
        var world = World()
        let spawned = world.spawn(Position(x: 1, y: 2), Velocity(dx: 3, dy: 4), Health(5))
        for (entity, position) in world.query(Position.self) {
            #expect(entity == spawned)
            #expect(position.x == 1)
        }
        for (entity, position, velocity) in world.query(Position.self, Velocity.self) {
            #expect(entity == spawned)
            #expect(position.y + velocity.dx == 5)
        }
        for (entity, position, velocity, health) in world.query(Position.self, Velocity.self, Health.self) {
            #expect(entity == spawned)
            #expect(position.x + velocity.dy + Double(health.current) == 10)
        }
    }

    @Test("A query of one type carries the component itself")
    func singleType() {
        var world = World()
        _ = world.spawn(Health(1))
        _ = world.spawn(Health(2))
        _ = world.spawn(Name("none"))
        let values = world.query(Health.self).map(\.1.current).sorted()
        #expect(values == [1, 2])
    }

    @Test("A query of no types lists every live entity")
    func noTypes() {
        var world = World()
        let a = world.spawn()
        let b = world.spawn(Health(1))
        let c = world.spawn()
        world.despawn(b)
        let rows = Array(world.query())
        #expect(rows == [a, c])
        #expect(world.query().count == 2)
    }

    @Test("A query of a type the world never stored is empty")
    func neverStored() {
        var world = World()
        _ = world.spawn(Health(1))
        #expect(world.query(Health.self, Name.self).count == 0)
        #expect(world.query(Name.self).count == 0)
    }

    @Test("A query of an empty world is empty")
    func emptyWorld() {
        let world = World()
        #expect(world.query(Health.self).count == 0)
        #expect(world.query().count == 0)
    }

    @Test("with keeps only entities holding the type, and without drops them")
    func filters() {
        var world = World()
        let frozen = world.spawn(Health(1), Frozen())
        let named = world.spawn(Health(2), Name("n"))
        let both = world.spawn(Health(3), Name("b"), Frozen())
        let plain = world.spawn(Health(4))
        #expect(world.query(Health.self).with(Frozen.self).map(\.entity).sorted() == [frozen, both])
        #expect(world.query(Health.self).without(Frozen.self).map(\.entity).sorted() == [named, plain])
        #expect(world.query(Health.self).with(Name.self).without(Frozen.self).map(\.entity) == [named])
        #expect(world.query(Health.self).with(Name.self, Frozen.self).map(\.entity) == [both])
        #expect(Array(world.query().with(Frozen.self)).sorted() == [frozen, both])
    }

    @Test("Requiring a type the world never stored gives nothing, and excluding one drops nothing")
    func filtersOnUnknownTypes() {
        var world = World()
        _ = world.spawn(Health(1))
        #expect(world.query(Health.self).with(Velocity.self).count == 0)
        #expect(world.query(Health.self).without(Velocity.self).count == 1)
    }

    @Test("filtered(by:) combines a reusable filter with the view's own")
    func filteredBy() {
        var world = World()
        let alive = world.spawn(Health(1), Name("a"))
        _ = world.spawn(Health(2), Name("b"), Frozen())
        _ = world.spawn(Health(3))
        let named = QueryFilter.with(Name.self)
        let rows = world.query(Health.self).without(Frozen.self).filtered(by: named).map(\.entity)
        #expect(rows == [alive])
    }

    @Test("Filters compose in any order", .tags(.conformance))
    func filterEquality() {
        let a = QueryFilter.with(Name.self).without(Frozen.self)
        let b = QueryFilter.without(Frozen.self).with(Name.self)
        #expect(a == b)
        #expect(a != QueryFilter())
    }

    @Test("A view is a snapshot: writing to the world while iterating does not change it", .tags(.copyOnWrite))
    func snapshot() {
        var world = World()
        for value in 0 ..< 4 { world.spawn(Health(value)) }
        var seen: [Int] = []
        for row in world.query(Health.self) {
            seen.append(row.1.current)
            world.despawn(row.entity)
            world.spawn(Health(100 + row.1.current))
        }
        #expect(seen.sorted() == [0, 1, 2, 3])
        #expect(world.query(Health.self).map(\.1.current).sorted() == [100, 101, 102, 103])
    }

    @Test("count agrees with iterating, with and without a filter")
    func countAgrees() {
        var world = World()
        for value in 0 ..< 10 {
            let entity = world.spawn(Health(value))
            if value.isMultiple(of: 3) { world.insert(Frozen(), into: entity) }
        }
        let view = world.query(Health.self)
        let filtered = view.without(Frozen.self)
        #expect(view.count == Array(view).count)
        #expect(filtered.count == Array(filtered).count)
        #expect(filtered.count == 6)
    }

    @Test("A view lists the world as it was when the view was made", .tags(.copyOnWrite))
    func viewAsOfCreation() {
        var world = World()
        let kept = world.spawn(Health(1))
        let despawned = world.spawn(Health(2))
        let view = world.query(Health.self)
        let entities = world.query()
        world.despawn(despawned)
        world.spawn(Health(3))
        world[Health.self, of: kept].current = 10
        let rows: [String] = view.map { "\($0.entity) \($0.1.current)" }.sorted()
        let expected: [String] = ["\(kept) 1", "\(despawned) 2"].sorted()
        let expectedEntities: [Entity] = [kept, despawned].sorted()
        #expect(rows == expected)
        #expect(Array(entities).sorted() == expectedEntities)
    }

    @Test("Rows come in the storage order of the queried or required type the fewest entities hold")
    func rowOrder() {
        var world = World()
        let a = world.spawn(Position(x: 0, y: 0))
        _ = world.spawn(Position(x: 0, y: 0))
        let c = world.spawn(Position(x: 0, y: 0))
        world.insert(Velocity(dx: 0, dy: 0), into: c)
        world.insert(Velocity(dx: 0, dy: 0), into: a)
        let expected: [Entity] = [c, a]
        #expect(world.query(Position.self, Velocity.self).map(\.entity) == expected)
        #expect(world.query(Velocity.self, Position.self).map(\.entity) == expected)
        #expect(world.query(Position.self).with(Velocity.self).map(\.entity) == expected)
        #expect(world.query(Query(Position.self, AnyOf<Velocity, Frozen>.self, Velocity.self)).map { $0.entity } == expected)
        #expect(Array(world.query().with(Velocity.self)) == expected)
    }

    @Test("A query of two types lists the smaller type's storage order, keeping the entities holding both", .tags(.randomized))
    func rowOrderMatchesModel() async {
        let operations = Gen.int(in: 0 ... 1_000_000).array(of: 0 ... 200)
        await propertyCheck(count: 100, input: operations) { operations in
            var world = World()
            var live: [Entity] = []
            for code in operations {
                let argument = code / 6
                guard !live.isEmpty, code % 6 != 0 else {
                    live.append(world.spawn())
                    continue
                }
                let entity = live[argument % live.count]
                switch code % 6 {
                case 1: world.insert(First(argument), into: entity)
                case 2: world.insert(Second(argument), into: entity)
                case 3: world.remove(First.self, from: entity)
                case 4: world.remove(Second.self, from: entity)
                default:
                    world.despawn(entity)
                    live.removeAll { $0 == entity }
                }
            }
            let firsts: [Entity] = world.query(First.self).map { $0.entity }
            let seconds: [Entity] = world.query(Second.self).map { $0.entity }
            let expected: [Entity] = firsts.count <= seconds.count
                ? firsts.filter { world.contains(Second.self, in: $0) }
                : seconds.filter { world.contains(First.self, in: $0) }
            let rows: [Entity] = world.query(First.self, Second.self).map { $0.entity }
            #expect(rows == expected)
        }
    }

    @Test("Each filter method of a query, a view and an entity view lists what the filter value's method of the same name does")
    func filterSpellingsAgree() {
        var world = World()
        let keep = world.spawn(Health(1))
        let gate = world.spawn(Health(2), Frozen())
        let sleeper = world.spawn(Health(3), Disabled())
        world.relate(keep, Guards(), to: gate)
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world[Health.self, of: gate].current = 5
        let fresh = world.spawn(Health(4))

        let with: [Entity] = [gate]
        #expect(world.query(Query(Health.self).with(Frozen.self)).map { $0.entity }.sorted() == with)
        #expect(world.query(Health.self).with(Frozen.self).map(\.entity).sorted() == with)
        #expect(Array(world.query().with(Health.self).with(Frozen.self)).sorted() == with)
        #expect(world.query(Health.self).filtered(by: .with(Frozen.self)).map(\.entity).sorted() == with)

        let without: [Entity] = [keep, fresh].sorted()
        #expect(world.query(Query(Health.self).without(Frozen.self)).map { $0.entity }.sorted() == without)
        #expect(world.query(Health.self).without(Frozen.self).map(\.entity).sorted() == without)
        #expect(Array(world.query().with(Health.self).without(Frozen.self)).sorted() == without)
        #expect(world.query(Health.self).filtered(by: .without(Frozen.self)).map(\.entity).sorted() == without)

        let allowing: [Entity] = [keep, gate, sleeper, fresh].sorted()
        #expect(world.query(Query(Health.self).allowing(Disabled.self)).map { $0.entity }.sorted() == allowing)
        #expect(world.query(Health.self).allowing(Disabled.self).map(\.entity).sorted() == allowing)
        #expect(Array(world.query().with(Health.self).allowing(Disabled.self)).sorted() == allowing)
        #expect(world.query(Health.self).filtered(by: .allowing(Disabled.self)).map(\.entity).sorted() == allowing)

        let related: [Entity] = [keep]
        #expect(world.query(Query(Health.self).related(Guards.self, to: gate)).map { $0.entity }.sorted() == related)
        #expect(world.query(Health.self).related(Guards.self, to: gate).map(\.entity).sorted() == related)
        #expect(Array(world.query().with(Health.self).related(Guards.self, to: gate)).sorted() == related)
        #expect(world.query(Health.self).filtered(by: .related(Guards.self, to: gate)).map(\.entity).sorted() == related)

        let added: [Entity] = [fresh]
        #expect(world.query(Query(Health.self).added(Health.self, since: checkpoint)).map { $0.entity }.sorted() == added)
        #expect(world.query(Health.self).added(Health.self, since: checkpoint).map(\.entity).sorted() == added)
        #expect(Array(world.query().added(Health.self, since: checkpoint)).sorted() == added)
        #expect(world.query(Health.self).filtered(by: .added(Health.self, since: checkpoint)).map(\.entity).sorted() == added)

        let changed: [Entity] = [gate, fresh].sorted()
        #expect(world.query(Query(Health.self).changed(Health.self, since: checkpoint)).map { $0.entity }.sorted() == changed)
        #expect(world.query(Health.self).changed(Health.self, since: checkpoint).map(\.entity).sorted() == changed)
        #expect(Array(world.query().changed(Health.self, since: checkpoint)).sorted() == changed)
        #expect(world.query(Health.self).filtered(by: .changed(Health.self, since: checkpoint)).map(\.entity).sorted() == changed)

        let anyOf: [Entity] = [keep, gate].sorted()
        let alternatives: QueryFilter = .anyOf(.with(Frozen.self), .related(Guards.self, to: gate))
        #expect(world.query(Query(Health.self).anyOf(.with(Frozen.self), .related(Guards.self, to: gate))).map { $0.entity }.sorted() == anyOf)
        #expect(world.query(Health.self).anyOf(.with(Frozen.self), .related(Guards.self, to: gate)).map(\.entity).sorted() == anyOf)
        #expect(Array(world.query().anyOf(.with(Frozen.self), .related(Guards.self, to: gate))).sorted() == anyOf)
        #expect(world.query(Health.self).filtered(by: alternatives).map(\.entity).sorted() == anyOf)
        #expect(Array(world.query().filtered(by: alternatives)).sorted() == anyOf)

        world.lastRun = checkpoint
        #expect(world.query(Query(Health.self).added(Health.self)).map { $0.entity } == added)
        #expect(world.query(Query(Health.self).changed(Health.self)).map { $0.entity }.sorted() == changed)
        #expect(Array(world.query().changed(Health.self)).sorted() == changed)
    }

    @Test("Without alternatives, anyOf on a view and on a filter value passes nothing")
    func emptyAnyOfSpellings() {
        var world = World()
        world.spawn(Health(1))
        let none: Int = 0
        #expect(world.query(Health.self).anyOf().count == none)
        #expect(world.query(Health.self).filtered(by: .anyOf()).count == none)
        #expect(world.query(Health.self).filtered(by: QueryFilter().anyOf()).count == none)
    }

    @Test("Iterating a query that no system bound to a world traps", .tags(.precondition))
    func unboundQueryTraps() async {
        await #expect(processExitsWith: .failure) {
            let query = Query(Position.self)
            for _ in query {}
        }
    }

    @Test("Iterating a Where whose query no system bound to a world traps", .tags(.precondition))
    func unboundWhereTraps() async {
        await #expect(processExitsWith: .failure) {
            let query = Query<Position>.Where<Without<Frozen>>(_bound: Query<Position>(filter: .without(Frozen.self)))
            for _ in query {}
        }
    }
}
