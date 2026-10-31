// Cached queries: the entities a query matches, kept current. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("World: cached queries")
struct QueryCacheTests {
    @Test("A cached query lists the rows an uncached one does")
    func sameRows() {
        var world = World()
        let moving = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Frozen())
        world.spawn(Position(x: 0, y: 0))
        world.spawn(Velocity(dx: 1, dy: 0))
        world.cache(Query(Position.self, Velocity.self).without(Frozen.self))
        let found: [Entity] = world.query(Query(Position.self, Velocity.self).without(Frozen.self)).map { $0.entity }
        let expected: [Entity] = [moving]
        #expect(found == expected)
    }

    @Test("A cache made before any entity exists fills as entities are spawned")
    func emptyWorld() {
        var world = World()
        world.cache(Query(Position.self, Velocity.self))
        let none: Int = 0
        #expect(world.query(Position.self, Velocity.self).count == none)
        let entity = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let found: [Entity] = world.query(Position.self, Velocity.self).map { $0.entity }
        let expected: [Entity] = [entity]
        #expect(found == expected)
    }

    @Test("Inserting, removing and despawning keep a cache current")
    func keptCurrent() {
        var world = World()
        world.cache(Query(Position.self, Velocity.self).without(Frozen.self))
        let query = Query(Position.self, Velocity.self).without(Frozen.self)
        let a = world.spawn(Position(x: 0, y: 0))
        let b = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        world.insert(Velocity(dx: 1, dy: 0), into: a)
        let both: Set<Entity> = [a, b]
        #expect(Set(world.query(query).map { $0.entity }) == both)
        world.insert(Frozen(), into: b)
        let onlyA: Set<Entity> = [a]
        #expect(Set(world.query(query).map { $0.entity }) == onlyA)
        world.remove(Frozen.self, from: b)
        #expect(Set(world.query(query).map { $0.entity }) == both)
        world.remove(Velocity.self, from: a)
        let onlyB: Set<Entity> = [b]
        #expect(Set(world.query(query).map { $0.entity }) == onlyB)
        world.despawn(b)
        let none: Set<Entity> = []
        #expect(Set(world.query(query).map { $0.entity }) == none)
    }

    @Test("A visit whose conditions imply a cache's lists what it would without the cache")
    func impliedVisits() {
        var world = World()
        let a = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Health(1))
        let b = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Health(2), Frozen())
        world.cache(Query(Position.self).without(Frozen.self))
        let narrower: Set<Entity> = Set(world.query(Query(Position.self, Health.self).without(Frozen.self)).map { $0.entity })
        let withHealth: Set<Entity> = [a]
        #expect(narrower == withHealth)
        world.update(Velocity.self, reading: Position.self, where: .without(Frozen.self)) { velocity, _ in velocity.dx = 5 }
        let moved: Velocity = Velocity(dx: 5, dy: 0)
        #expect(world[Velocity.self, of: a] == moved)
        #expect(world[Velocity.self, of: b] == moved)
        let frozen: Int = 1
        #expect(world.query(Velocity.self).filter { $0.1.dx == 1 }.count == frozen)
    }

    @Test("A visit that does not exclude what a cache excludes ignores the cache")
    func broaderVisits() {
        var world = World()
        world.spawn(Position(x: 0, y: 0))
        world.spawn(Position(x: 0, y: 0), Frozen())
        world.cache(Query(Position.self).without(Frozen.self))
        let all: Int = 2
        #expect(world.query(Position.self).count == all)
    }

    @Test("An AnyOf term does not narrow a cache, and its query still matches either type")
    func anyOfTerm() {
        var world = World()
        let first = world.spawn(Position(x: 0, y: 0), First(1))
        let second = world.spawn(Position(x: 0, y: 0), Second(2))
        world.spawn(Position(x: 0, y: 0))
        let query = Query(Position.self, AnyOf<First, Second>.self)
        world.cache(query)
        let found: Set<Entity> = Set(world.query(query).map { $0.entity })
        let expected: Set<Entity> = [first, second]
        #expect(found == expected)
        world.update(Position.self, over: Query(AnyOf<First, Second>.self)) { position, _ in position.x = 1 }
        let moved: Int = 2
        #expect(world.query(Position.self).filter { $0.1.x == 1 }.count == moved)
    }

    @Test("Disabling an entity drops it from a cache; a query allowing Disabled still lists it")
    func disabled() {
        var world = World()
        let entity = world.spawn(Position(x: 0, y: 0))
        world.cache(Query(Position.self))
        world.insert(Disabled(), into: entity)
        let none: Int = 0
        #expect(world.query(Position.self).count == none)
        let found: [Entity] = world.query(Query(Position.self).allowing(Disabled.self)).map { $0.entity }
        let expected: [Entity] = [entity]
        #expect(found == expected)
        world.remove(Disabled.self, from: entity)
        #expect(world.query(Position.self).map { $0.entity } == expected)
    }

    @Test("Change filters on a cached query are checked for each cached entity")
    func changeFilters() {
        var world = World()
        let a = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let query = Query(Position.self, Velocity.self).changed(Position.self, since: world.changeTick)
        world.cache(query)
        world.advanceChangeTick()
        world[Position.self, of: a].x = 3
        let found: [Entity] = world.query(query).map { $0.entity }
        let expected: [Entity] = [a]
        #expect(found == expected)
    }

    @Test("A copy of a world keeps its own cache")
    func copies() {
        var world = World()
        world.cache(Query(Position.self).without(Frozen.self))
        let entity = world.spawn(Position(x: 0, y: 0))
        let copy = world
        world.insert(Frozen(), into: entity)
        let none: Int = 0
        let one: Int = 1
        #expect(world.query(Query(Position.self).without(Frozen.self)).count == none)
        #expect(copy.query(Query(Position.self).without(Frozen.self)).count == one)
    }

    @Test("Concurrent changes that insert and remove cached types leave the cache current")
    func concurrentChanges() {
        var world = World()
        let a = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let b = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Frozen())
        let query = Query(Position.self, Velocity.self).without(Frozen.self)
        world.cache(query)
        world.runConcurrently([
            ConcurrentChange(access: .writes(Frozen.self)) { world in
                world.insert(Frozen(), into: a)
                world.remove(Frozen.self, from: b)
            },
            ConcurrentChange(access: .writes(Position.self)) { world in
                world.update(Position.self) { position, _ in position.x += 1 }
            },
        ])
        let found: [Entity] = world.query(query).map { $0.entity }
        let expected: [Entity] = [b]
        #expect(found == expected)
    }

    @Test("A part that changes cached types rebuilds the cache once every part is merged back")
    func splitParts() {
        var world = World()
        let a = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let query = Query(Position.self, Velocity.self).without(Frozen.self)
        world.cache(query)
        let frozenAccess = Access.writes(Frozen.self)
        let positionAccess = Access.writes(Position.self)
        var frozenPart = world.split(writing: frozenAccess)
        var positionPart = world.split(writing: positionAccess)
        frozenPart.insert(Frozen(), into: a)
        positionPart.update(Position.self) { position, _ in position.x = 2 }
        world.merge(writing: frozenAccess, from: frozenPart)
        world.merge(writing: positionAccess, from: positionPart)
        let none: Int = 0
        #expect(world.query(query).count == none)
        world.remove(Frozen.self, from: a)
        let found: [Entity] = world.query(query).map { $0.entity }
        let expected: [Entity] = [a]
        #expect(found == expected)
    }

    @Test("Queries and updates agree with an uncached world under random changes", .tags(.randomized))
    func matchesUncached() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var cached = World()
            cached.cache(Query(Position.self, Velocity.self).without(Frozen.self))
            cached.cache(Query(Health.self).with(Name.self))
            var plain = World()
            var alive: [Entity] = []
            for _ in 0 ..< Int.random(in: 0 ... 60, using: &generator) {
                let choice = Int.random(in: 0 ..< 6, using: &generator)
                if choice == 0 || alive.isEmpty {
                    let entity = cached.spawn(Position(x: 0, y: 0))
                    let same = plain.spawn(Position(x: 0, y: 0))
                    #expect(entity == same)
                    alive.append(entity)
                    continue
                }
                let entity = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                switch choice {
                case 1:
                    cached.insert(Velocity(dx: 1, dy: 0), into: entity)
                    plain.insert(Velocity(dx: 1, dy: 0), into: entity)
                case 2:
                    cached.insert(Frozen(), into: entity)
                    plain.insert(Frozen(), into: entity)
                case 3:
                    cached.remove(Frozen.self, from: entity)
                    plain.remove(Frozen.self, from: entity)
                case 4:
                    cached.insert(Health(1), Name("n"), into: entity)
                    plain.insert(Health(1), Name("n"), into: entity)
                default:
                    cached.despawn(entity)
                    plain.despawn(entity)
                    alive.removeAll { $0 == entity }
                }
            }
            cached.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, _ in position.x += 1 }
            plain.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, _ in position.x += 1 }
            let query = Query(Position.self, Velocity.self).without(Frozen.self)
            let cachedRows: [Entity] = cached.query(query).map { $0.entity }.sorted()
            let plainRows: [Entity] = plain.query(query).map { $0.entity }.sorted()
            #expect(cachedRows == plainRows)
            let healthQuery = Query(Health.self).with(Name.self)
            let cachedHealth: [Entity] = cached.query(healthQuery).map { $0.entity }.sorted()
            let plainHealth: [Entity] = plain.query(healthQuery).map { $0.entity }.sorted()
            #expect(cachedHealth == plainHealth)
            let cachedPositions = cached.snapshot(Position.self)
            let plainPositions = plain.snapshot(Position.self)
            #expect(cachedPositions == plainPositions)
        }
    }
}
