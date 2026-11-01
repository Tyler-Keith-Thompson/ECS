// Spawning many entities at once. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

/// A component that brings a health of its own.
private struct Shielded: Component {
    var rating: Int
    static var required: some WorldModule.Bundle { Health(9) }
}

/// A component and a health, spawned together.
private struct Crate: WorldModule.Bundle {
    var x: Double
    var body: some WorldModule.Bundle {
        Position(x: x, y: 0)
        Health(1)
    }
}

/// Counts what hooks see.
private struct HookCount: Resource {
    var added = 0
}

@Suite("World: spawning many entities")
struct BatchSpawnTests {
    @Test("Spawning a sequence of components, pairs and triples gives each entity its components, in order")
    func arities() {
        var world = World()
        let singles = world.spawn(contentsOf: [Health(1), Health(2)])
        let pairs = world.spawn(contentsOf: [(Position(x: 1, y: 1), Velocity(dx: 1, dy: 0)), (Position(x: 2, y: 2), Velocity(dx: 2, dy: 0))])
        let triples = world.spawn(contentsOf: [(Name("a"), Position(x: 3, y: 3), Health(3))])
        let singleCount = 2
        let pairCount = 2
        let tripleCount = 1
        #expect(singles.count == singleCount)
        #expect(pairs.count == pairCount)
        #expect(triples.count == tripleCount)
        let secondHealth = Health(2)
        let secondVelocity = Velocity(dx: 2, dy: 0)
        let tripleName = Name("a")
        let tripleHealth = Health(3)
        #expect(world[Health.self, of: singles[1]] == secondHealth)
        #expect(world[Velocity.self, of: pairs[1]] == secondVelocity)
        #expect(world[Name.self, of: triples[0]] == tripleName)
        #expect(world[Health.self, of: triples[0]] == tripleHealth)
        let total = 5
        #expect(world.count == total)
    }

    @Test("An empty sequence spawns nothing")
    func empty() {
        var world = World()
        let none: [Entity] = []
        let noHealth: [Health] = []
        let noPairs: [(Position, Velocity)] = []
        #expect(world.spawn(contentsOf: noHealth) == none)
        #expect(world.spawn(contentsOf: noPairs) == none)
        #expect(world.isEmpty)
    }

    @Test("Spawning many reuses vacant slots first, giving the handles one-at-a-time spawning would")
    func vacantSlots() {
        var batched = World()
        let first = batched.spawn(contentsOf: [Health(1), Health(2), Health(3)])
        batched.despawn(first[0])
        batched.despawn(first[2])
        let reused = batched.spawn(contentsOf: [Health(4), Health(5), Health(6)])
        var expected = World()
        let expectedFirst = [expected.spawn(Health(1)), expected.spawn(Health(2)), expected.spawn(Health(3))]
        expected.despawn(expectedFirst[0])
        expected.despawn(expectedFirst[2])
        let expectedReused = [expected.spawn(Health(4)), expected.spawn(Health(5)), expected.spawn(Health(6))]
        #expect(reused == expectedReused)
        let values = reused.map { batched[Health.self, of: $0].current }
        let expectedValues = [4, 5, 6]
        #expect(values == expectedValues)
    }

    @Test("Hooks, required components, indexes, groups, caches and change logs see every entity spawned in a batch")
    func watchedSpawns() {
        var world = World()
        world.resources.insert(HookCount())
        world.onAdd(Velocity.self) { world, _ in world.resources[HookCount.self].added += 1 }
        let hooked = world.spawn(contentsOf: [(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0)), (Position(x: 0, y: 0), Velocity(dx: 2, dy: 0))])
        let hookCount = 2
        #expect(world.resources[HookCount.self].added == hookCount)
        #expect(hooked.count == hookCount)

        var required = World()
        let shielded = required.spawn(contentsOf: [Shielded(rating: 1)])
        let requiredHealth = Health(9)
        #expect(required[Health.self, of: shielded[0]] == requiredHealth)

        var indexed = World()
        indexed.index(Health.self)
        let indexedEntities = indexed.spawn(contentsOf: [Health(7), Health(8)])
        let atSeven: [Entity] = [indexedEntities[0]]
        #expect(indexed.lookup(Health(7)) == atSeven)

        var grouped = World()
        grouped.group(Position.self, Velocity.self)
        let groupedEntities = grouped.spawn(contentsOf: [(Position(x: 0, y: 0), Velocity(dx: 3, dy: 0))])
        grouped.update(Position.self, reading: Velocity.self) { position, row in position.x += row.components.dx }
        let movedX = 3.0
        #expect(grouped[Position.self, of: groupedEntities[0]].x == movedX)

        var cached = World()
        let movers = Query(Position.self, Velocity.self)
        cached.cache(movers)
        _ = cached.spawn(contentsOf: [(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))])
        let cachedCount = 1
        #expect(cached.query(movers).count == cachedCount)

        var tracked = World()
        tracked.trackChanges(of: Health.self)
        let checkpoint = tracked.changeTick
        tracked.advanceChangeTick()
        let trackedEntities = tracked.spawn(contentsOf: [Health(1), Health(2)])
        let added = Set(tracked.query(Health.self).added(Health.self, since: checkpoint).map(\.entity))
        #expect(added == Set(trackedEntities))
    }

    @Test("A pair of the same type keeps the later component, as spawning one at a time does")
    func repeatedType() {
        var world = World()
        let entities = world.spawn(contentsOf: [(Health(1), Health(2))])
        let later = Health(2)
        #expect(world[Health.self, of: entities[0]] == later)
    }

    @Test("Spawning a sequence of bundles spawns each bundle's components")
    func bundles() {
        var world = World()
        let crates = world.spawn(contentsOf: [Crate(x: 1), Crate(x: 2)])
        let secondX = 2.0
        let health = Health(1)
        #expect(world[Position.self, of: crates[1]].x == secondX)
        #expect(world[Health.self, of: crates[0]] == health)
    }

    @Test("Spawned components are stamped added and changed at the current tick")
    func ticks() {
        var world = World()
        world.spawn(Health(0))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        let entities = world.spawn(contentsOf: [Health(1), Health(2)])
        let added = Set(world.query(Health.self).added(Health.self, since: checkpoint).map(\.entity))
        #expect(added == Set(entities))
    }

    @Test("Batch spawning agrees with one-at-a-time spawning under random spawns and despawns", .tags(.randomized))
    func matchesSingleSpawns() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var batched = World()
            var single = World()
            var alive: [Entity] = []
            for _ in 0 ..< Int.random(in: 0 ... 20, using: &generator) {
                if Bool.random(using: &generator) || alive.isEmpty {
                    let count = Int.random(in: 0 ... 5, using: &generator)
                    let rows = (0 ..< count).map { _ in
                        (Position(x: Double(Int.random(in: 0 ..< 9, using: &generator)), y: 0), Health(Int.random(in: 0 ..< 9, using: &generator)))
                    }
                    let spawned = batched.spawn(contentsOf: rows)
                    var expected: [Entity] = []
                    for row in rows { expected.append(single.spawn(row.0, row.1)) }
                    #expect(spawned == expected)
                    alive += spawned
                } else {
                    let entity = alive.remove(at: Int.random(in: 0 ..< alive.count, using: &generator))
                    batched.despawn(entity)
                    single.despawn(entity)
                }
            }
            let batchedRows = batched.query(Position.self, Health.self).map { "\($0.entity) \($0.1.x) \($0.2.current)" }.sorted()
            let singleRows = single.query(Position.self, Health.self).map { "\($0.entity) \($0.1.x) \($0.2.current)" }.sorted()
            #expect(batchedRows == singleRows)
            #expect(batched.count == single.count)
        }
    }
}
