// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import Testing
import WorldModule

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

    @Test("A row carries its components in the order the query listed their types")
    func componentOrder() throws {
        var world = World()
        _ = world.spawn(Velocity(dx: 3, dy: 4), Position(x: 1, y: 2))
        let row = try #require(world.query(Position.self, Velocity.self).first { _ in true })
        let (position, velocity) = row.components
        let expectedPosition = Position(x: 1, y: 2)
        let expectedVelocity = Velocity(dx: 3, dy: 4)
        #expect(position == expectedPosition)
        #expect(velocity == expectedVelocity)
    }

    @Test("A query of one type carries the component itself")
    func singleType() {
        var world = World()
        _ = world.spawn(Health(1))
        _ = world.spawn(Health(2))
        _ = world.spawn(Name("none"))
        let values = world.query(Health.self).map(\.components.current).sorted()
        #expect(values == [1, 2])
    }

    @Test("A query of no types lists every live entity")
    func noTypes() {
        var world = World()
        let a = world.spawn()
        let b = world.spawn(Health(1))
        let c = world.spawn()
        world.despawn(b)
        let rows = world.query().map(\.entity)
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
        #expect(world.query().with(Frozen.self).map(\.entity).sorted() == [frozen, both])
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
            seen.append(row.components.current)
            world.despawn(row.entity)
            world.spawn(Health(100 + row.components.current))
        }
        #expect(seen.sorted() == [0, 1, 2, 3])
        #expect(world.query(Health.self).map(\.components.current).sorted() == [100, 101, 102, 103])
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
}
