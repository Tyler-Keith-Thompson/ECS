// Spans over a component type's storage. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("World: column spans")
struct SpanTests {
    struct Stop: Error, Equatable {}

    @Test("A type no entity holds gives empty spans")
    func emptyType() {
        let world = World()
        func counts(_ entities: Span<Entity>, _ values: Span<Health>) -> [Int] {
            [entities.count, values.count]
        }
        let found: [Int] = world.withSpan(of: Health.self, counts)
        let expected: [Int] = [0, 0]
        #expect(found == expected)
    }

    @Test("A mutable span of a type no entity holds is empty and leaves the world without the type")
    func emptyMutableType() {
        var world = World()
        // A closure literal: Swift 6.3 cannot pass a named function taking an inout MutableSpan.
        let found: Int = world.withMutableSpan(of: Health.self) { entities, values in
            entities.count + values.count
        }
        let expected: Int = 0
        #expect(found == expected)
        #expect(world.query(Health.self).count == expected)
    }

    @Test("The component at each position belongs to the entity at the same position")
    func positionsAgree() {
        var world = World()
        let a = world.spawn(Health(1))
        let b = world.spawn(Health(2))
        let c = world.spawn(Health(3))
        world.despawn(a)
        func pairs(_ entities: Span<Entity>, _ values: Span<Health>) -> [Entity: Int] {
            var result: [Entity: Int] = [:]
            for position in entities.indices { result[entities[position]] = values[position].current }
            return result
        }
        let found: [Entity: Int] = world.withSpan(of: Health.self, pairs)
        let expected: [Entity: Int] = [b: 2, c: 3]
        #expect(found == expected)
    }

    @Test("A span includes disabled entities")
    func includesDisabled() {
        var world = World()
        world.spawn(Health(1))
        world.spawn(Health(2), Disabled())
        func sum(_ entities: Span<Entity>, _ values: Span<Health>) -> Int {
            var total = 0
            for position in values.indices { total += values[position].current }
            return total
        }
        let found: Int = world.withSpan(of: Health.self, sum)
        let expected: Int = 3
        #expect(found == expected)
    }

    @Test("Writing through a mutable span changes the components and marks each changed")
    func mutationMarksChanged() {
        var world = World()
        let a = world.spawn(Health(1))
        let b = world.spawn(Health(2))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world.withMutableSpan(of: Health.self) { _, values in
            for position in values.indices { values[position].current *= 2 }
        }
        let first: Health = Health(2)
        let second: Health = Health(4)
        #expect(world[Health.self, of: a] == first)
        #expect(world[Health.self, of: b] == second)
        let changed: Set<Entity> = Set(world.query().changed(Health.self, since: checkpoint))
        let expected: Set<Entity> = [a, b]
        #expect(changed == expected)
    }

    @Test("A mutable span copies storage another world shares, leaving that world unchanged")
    func copyOnWrite() {
        var world = World()
        let entity = world.spawn(Health(1))
        let copy = world
        world.withMutableSpan(of: Health.self) { _, values in
            for position in values.indices { values[position].current = 9 }
        }
        let original: Health = Health(1)
        let written: Health = Health(9)
        #expect(copy[Health.self, of: entity] == original)
        #expect(world[Health.self, of: entity] == written)
    }

    @Test("A body's typed error passes through a span")
    func throwingBody() {
        let world = {
            var world = World()
            world.spawn(Health(1))
            return world
        }()
        func fail(_ entities: Span<Entity>, _ values: Span<Health>) throws(Stop) -> Int {
            throw Stop()
        }
        #expect(throws: Stop()) {
            try world.withSpan(of: Health.self, fail)
        }
    }

    @Test("A throwing mutable span body keeps the writes made before the error and marks them changed")
    func throwingMutableBody() {
        var world = World()
        let a = world.spawn(Health(1))
        let b = world.spawn(Health(2))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        var caught: Stop?
        do {
            try world.withMutableSpan(of: Health.self) { _, values throws(Stop) in
                values[0].current = 7
                throw Stop()
            }
        } catch {
            caught = error
        }
        let stop: Stop? = Stop()
        #expect(caught == stop)
        let healths: [Int] = [world[Health.self, of: a].current, world[Health.self, of: b].current].sorted()
        let expected: [Int] = [2, 7]
        #expect(healths == expected)
        let changed: Set<Entity> = Set(world.query().changed(Health.self, since: checkpoint))
        let all: Set<Entity> = [a, b]
        #expect(changed == all)
    }

    @Test("A sum through a span matches a sum through a query", .tags(.randomized))
    func matchesQuery() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            var alive: [Entity] = []
            for _ in 0 ..< Int.random(in: 0 ... 40, using: &generator) {
                alive.append(world.spawn(Health(Int.random(in: -100 ... 100, using: &generator))))
                if !alive.isEmpty, Bool.random(using: &generator) {
                    world.despawn(alive.remove(at: Int.random(in: 0 ..< alive.count, using: &generator)))
                }
            }
            func sum(_ entities: Span<Entity>, _ values: Span<Health>) -> Int {
                var total = 0
                for position in values.indices { total += values[position].current }
                return total
            }
            let found: Int = world.withSpan(of: Health.self, sum)
            let expected: Int = world.query(Health.self).reduce(0) { total, row in total + row.1.current }
            #expect(found == expected)
        }
    }
}
