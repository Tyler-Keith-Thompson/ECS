// Ordered indexes of components by a property: range lookups and visits in key order. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

/// A runner's place in a race, compared by position.
private struct Standing: Component, Hashable {
    var position: Int
    var lane: Int
}

/// How far back a sprite is drawn.
private struct Depth: Component {
    var z: Double
}

/// The integers greater than a floor: a kind of range an ordered index has no bounds for.
private struct Above: RangeExpression {
    let floor: Int

    func relative<C: Collection>(to collection: C) -> Range<Int> where C.Index == Int {
        Swift.min(floor + 1, collection.endIndex) ..< collection.endIndex
    }

    func contains(_ element: Int) -> Bool { element > floor }
}

@Suite("World: ordered indexes")
struct OrderedIndexTests {
    @Test("A range lookup finds the entities whose key falls in each kind of range, in key order, with or without an index")
    func rangeKinds() {
        var world = World()
        let third = world.spawn(Standing(position: 3, lane: 1))
        let first = world.spawn(Standing(position: 1, lane: 2))
        let fifth = world.spawn(Standing(position: 5, lane: 3))
        let second = world.spawn(Standing(position: 2, lane: 4))
        let halfOpen: [Entity] = [second, third]
        let closed: [Entity] = [second, third, fifth]
        let from: [Entity] = [third, fifth]
        let through: [Entity] = [first, second]
        let upTo: [Entity] = [first]
        let above: [Entity] = [fifth]
        for indexed in [false, true] {
            if indexed { world.index(ordered: \Standing.position) }
            #expect(world.lookup(\Standing.position, in: 2 ..< 4) == halfOpen)
            #expect(world.lookup(\Standing.position, in: 2 ... 5) == closed)
            #expect(world.lookup(\Standing.position, in: 3...) == from)
            #expect(world.lookup(\Standing.position, in: ...2) == through)
            #expect(world.lookup(\Standing.position, in: ..<2) == upTo)
            #expect(world.lookup(\Standing.position, in: Above(floor: 3)) == above)
        }
    }

    @Test("Entities with equal keys come back in entity order, with or without an index")
    func ties() {
        var world = World()
        let a = world.spawn(Standing(position: 2, lane: 1))
        let b = world.spawn(Standing(position: 1, lane: 2))
        let c = world.spawn(Standing(position: 2, lane: 3))
        let d = world.spawn(Standing(position: 1, lane: 4))
        let expected: [Entity] = [b, d, a, c]
        #expect(world.entities(sortedBy: \Standing.position) == expected)
        #expect(world.lookup(\Standing.position, in: 1 ... 2) == expected)
        world.index(ordered: \Standing.position)
        #expect(world.entities(sortedBy: \Standing.position) == expected)
        #expect(world.lookup(\Standing.position, in: 1 ... 2) == expected)
    }

    @Test("Empty ranges, ranges past every key, one entity and an unstored type")
    func edges() {
        var world = World()
        let none: [Entity] = []
        #expect(world.lookup(\Standing.position, in: 0...) == none)
        #expect(world.entities(sortedBy: \Standing.position) == none)
        world.index(ordered: \Standing.position)
        #expect(world.lookup(\Standing.position, in: 0...) == none)
        #expect(world.entities(sortedBy: \Standing.position) == none)
        let only = world.spawn(Standing(position: 4, lane: 0))
        let onlyOne: [Entity] = [only]
        #expect(world.lookup(\Standing.position, in: 4 ..< 4) == none)
        #expect(world.lookup(\Standing.position, in: 5...) == none)
        #expect(world.lookup(\Standing.position, in: ..<4) == none)
        #expect(world.lookup(\Standing.position, in: 4 ... 4) == onlyOne)
        #expect(world.lookup(\Standing.position, in: Int.min ... Int.max) == onlyOne)
        #expect(world.entities(sortedBy: \Standing.position) == onlyOne)
    }

    @Test("Spawning, inserting, removing and despawning keep an ordered index current")
    func keptCurrent() {
        var world = World()
        world.index(ordered: \Standing.position)
        let a = world.spawn(Standing(position: 3, lane: 0))
        let b = world.spawn(Name("b"))
        world.insert(Standing(position: 1, lane: 0), into: b)
        let c = world.spawn(Standing(position: 2, lane: 0))
        let afterSpawns: [Entity] = [b, c, a]
        #expect(world.entities(sortedBy: \Standing.position) == afterSpawns)
        world.insert(Standing(position: 9, lane: 0), into: b)
        let afterMove: [Entity] = [c, a, b]
        #expect(world.entities(sortedBy: \Standing.position) == afterMove)
        _ = world.remove(Standing.self, from: c)
        world.despawn(a)
        let onlyB: [Entity] = [b]
        #expect(world.entities(sortedBy: \Standing.position) == onlyB)
        let none: [Entity] = []
        #expect(world.lookup(\Standing.position, in: ...8) == none)
    }

    @Test("A change in place is found at once, and the ordered index is rebuilt at the next tick")
    func changesInPlace() {
        var world = World()
        world.index(ordered: \Standing.position)
        let a = world.spawn(Standing(position: 1, lane: 0))
        let b = world.spawn(Standing(position: 2, lane: 0))
        world[Standing.self, of: a].position = 5
        let reordered: [Entity] = [b, a]
        #expect(world.entities(sortedBy: \Standing.position) == reordered)
        world.update(Standing.self) { standing, _ in standing.position = -standing.position }
        world.advanceChangeTick()
        let negated: [Entity] = [a, b]
        #expect(world.entities(sortedBy: \Standing.position) == negated)
        let onlyA: [Entity] = [a]
        #expect(world.lookup(\Standing.position, in: ..<(-3)) == onlyA)
        world.insert(Standing(position: -9, lane: 0), into: b)
        let afterInsert: [Entity] = [b, a]
        #expect(world.entities(sortedBy: \Standing.position) == afterInsert)
    }

    @Test("A copy of a world keeps its own ordered index")
    func copies() {
        var world = World()
        world.index(ordered: \Standing.position)
        let a = world.spawn(Standing(position: 1, lane: 0))
        var copy = world
        let b = copy.spawn(Standing(position: 0, lane: 0))
        let original: [Entity] = [a]
        let copied: [Entity] = [b, a]
        #expect(world.entities(sortedBy: \Standing.position) == original)
        #expect(copy.entities(sortedBy: \Standing.position) == copied)
    }

    @Test("Indexing a key path ordered twice keeps one index, alongside an index by value on the same key path")
    func twiceAndAlongside() {
        var world = World()
        let a = world.spawn(Standing(position: 2, lane: 0))
        world.index(ordered: \Standing.position)
        world.index(ordered: \Standing.position)
        world.index(\Standing.position)
        world.index(ordered: \Standing.lane)
        let b = world.spawn(Standing(position: 1, lane: 1))
        world.insert(Standing(position: 3, lane: 2), into: a)
        let byPosition: [Entity] = [b, a]
        let byLane: [Entity] = [b, a]
        let atThree: [Entity] = [a]
        #expect(world.entities(sortedBy: \Standing.position) == byPosition)
        #expect(world.entities(sortedBy: \Standing.lane) == byLane)
        #expect(world.lookup(\Standing.position, equals: 3) == atThree)
    }

    @Test("A NaN key traps when indexed")
    func nanIndexed() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.spawn(Depth(z: .nan))
            world.index(ordered: \Depth.z)
        }
    }

    @Test("A NaN key traps when inserted into an indexed type")
    func nanInserted() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.index(ordered: \Depth.z)
            world.spawn(Depth(z: .nan))
        }
    }

    @Test("A NaN key traps in an unindexed range lookup and sort")
    func nanUnindexed() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.spawn(Depth(z: .nan))
            _ = world.lookup(\Depth.z, in: 0.0...)
        }
        await #expect(processExitsWith: .failure) {
            var world = World()
            world.spawn(Depth(z: .nan))
            _ = world.entities(sortedBy: \Depth.z)
        }
    }

    @Test("Ordered lookups agree with a sorted scan under random changes", .tags(.randomized))
    func matchesScan() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            world.index(ordered: \Standing.position)
            var alive: [Entity] = []
            func randomStanding() -> Standing {
                Standing(position: Int.random(in: 0 ..< 8, using: &generator), lane: Int.random(in: 0 ..< 3, using: &generator))
            }
            for _ in 0 ..< Int.random(in: 0 ... 80, using: &generator) {
                let choice = Int.random(in: 0 ..< 7, using: &generator)
                if choice == 0 || alive.isEmpty {
                    alive.append(world.spawn(randomStanding()))
                    continue
                }
                let entity = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                switch choice {
                case 1: world.insert(randomStanding(), into: entity)
                case 2: _ = world.remove(Standing.self, from: entity)
                case 3:
                    if world.contains(Standing.self, in: entity) {
                        world[Standing.self, of: entity].position = Int.random(in: 0 ..< 8, using: &generator)
                    }
                case 4: world.advanceChangeTick()
                case 5: world.update(Standing.self) { standing, _ in standing.position = (standing.position + 3) % 8 }
                default:
                    world.despawn(entity)
                    alive.removeAll { $0 == entity }
                }
            }
            let rows = world.query(Standing.self).map { (entity: $0.entity, position: $0.1.position) }
            func scan(_ matches: (Int) -> Bool) -> [Entity] {
                rows.filter { matches($0.position) }
                    .sorted { ($0.position, $0.entity) < ($1.position, $1.entity) }
                    .map(\.entity)
            }
            let low = Int.random(in: 0 ..< 8, using: &generator)
            let high = Int.random(in: low ..< 9, using: &generator)
            let all = scan { _ in true }
            let halfOpen = scan { $0 >= low && $0 < high }
            let closed = scan { $0 >= low && $0 <= high }
            let from = scan { $0 >= low }
            let through = scan { $0 <= high }
            let upTo = scan { $0 < high }
            #expect(world.entities(sortedBy: \Standing.position) == all)
            #expect(world.lookup(\Standing.position, in: low ..< high) == halfOpen)
            #expect(world.lookup(\Standing.position, in: low ... high) == closed)
            #expect(world.lookup(\Standing.position, in: low...) == from)
            #expect(world.lookup(\Standing.position, in: ...high) == through)
            #expect(world.lookup(\Standing.position, in: ..<high) == upTo)
        }
    }
}
