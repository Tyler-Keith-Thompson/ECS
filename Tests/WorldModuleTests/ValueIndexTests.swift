// Indexes of components by value. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

/// An actor's place in a scene, found by one field or two without knowing the others.
private struct Place: Component, Hashable {
    var set: Int
    var record: Int
    var slot: Int
}

@Suite("World: indexes by value")
struct ValueIndexTests {
    @Test("A lookup finds the entities holding a value, with or without an index")
    func lookup() {
        var world = World()
        let bob = world.spawn(Name("bob"))
        let alice = world.spawn(Name("alice"))
        let otherBob = world.spawn(Name("bob"))
        let bobs: Set<Entity> = [bob, otherBob]
        let alices: Set<Entity> = [alice]
        #expect(Set(world.lookup(Name("bob"))) == bobs)
        world.index(Name.self)
        #expect(Set(world.lookup(Name("bob"))) == bobs)
        #expect(Set(world.lookup(Name("alice"))) == alices)
        let none: [Entity] = []
        #expect(world.lookup(Name("carol")) == none)
        #expect(world.lookup(Health(1)) == none)
    }

    @Test("Spawning, inserting, removing and despawning keep an index current")
    func keptCurrent() {
        var world = World()
        world.index(Name.self)
        let a = world.spawn(Name("a"))
        let b = world.spawn(Position(x: 0, y: 0))
        world.insert(Name("a"), into: b)
        let both: Set<Entity> = [a, b]
        #expect(Set(world.lookup(Name("a"))) == both)
        world.insert(Name("z"), into: a)
        let onlyB: [Entity] = [b]
        let onlyA: [Entity] = [a]
        #expect(world.lookup(Name("a")) == onlyB)
        #expect(world.lookup(Name("z")) == onlyA)
        world.remove(Name.self, from: b)
        let none: [Entity] = []
        #expect(world.lookup(Name("a")) == none)
        world.despawn(a)
        #expect(world.lookup(Name("z")) == none)
    }

    @Test("A change in place is found at once, and the index is rebuilt at the next tick")
    func changesInPlace() {
        var world = World()
        world.index(Name.self)
        let a = world.spawn(Name("a"))
        let b = world.spawn(Name("b"))
        world[Name.self, of: a].text = "c"
        let onlyA: [Entity] = [a]
        let none: [Entity] = []
        #expect(world.lookup(Name("c")) == onlyA)
        #expect(world.lookup(Name("a")) == none)
        world.update(Name.self) { name, _ in name.text += "!" }
        world.advanceChangeTick()
        let onlyB: [Entity] = [b]
        #expect(world.lookup(Name("b!")) == onlyB)
        #expect(world.lookup(Name("c!")) == onlyA)
        world.insert(Name("d"), into: b)
        #expect(world.lookup(Name("d")) == onlyB)
    }

    @Test("A change in place through a mutable span is found at once, before the index is rebuilt")
    func mutableSpanChange() {
        var world = World()
        world.index(Name.self)
        let a = world.spawn(Name("a"))
        world.withMutableSpan(of: Name.self) { _, values in
            for position in values.indices { values[position].text = "b" }
        }
        let onlyA: [Entity] = [a]
        let none: [Entity] = []
        #expect(world.lookup(Name("b")) == onlyA)
        #expect(world.lookup(Name("a")) == none)
        world.advanceChangeTick()
        #expect(world.lookup(Name("b")) == onlyA)
    }

    @Test("A copy of a world keeps its own index")
    func copies() {
        var world = World()
        world.index(Name.self)
        let a = world.spawn(Name("a"))
        let copy = world
        world.insert(Name("b"), into: a)
        let onlyA: [Entity] = [a]
        #expect(copy.lookup(Name("a")) == onlyA)
        #expect(world.lookup(Name("b")) == onlyA)
        let none: [Entity] = []
        #expect(world.lookup(Name("a")) == none)
    }

    @Test("Indexing a type twice keeps one index, and indexing an unstored type works")
    func twice() {
        var world = World()
        world.index(Health.self)
        world.index(Health.self)
        let a = world.spawn(Health(3))
        let onlyA: [Entity] = [a]
        #expect(world.lookup(Health(3)) == onlyA)
    }

    @Test("A concurrent change writing an indexed type leaves lookups current")
    func concurrentChange() {
        var world = World()
        world.index(Name.self)
        let a = world.spawn(Name("a"))
        world.runConcurrently([
            ConcurrentChange(access: .writes(Name.self)) { world in
                world.insert(Name("b"), into: a)
            },
        ])
        let onlyA: [Entity] = [a]
        let none: [Entity] = []
        #expect(world.lookup(Name("b")) == onlyA)
        #expect(world.lookup(Name("a")) == none)
        world.advanceChangeTick()
        #expect(world.lookup(Name("b")) == onlyA)
    }

    @Test("Lookups agree with a scan under random changes", .tags(.randomized))
    func matchesScan() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            world.index(Health.self)
            var alive: [Entity] = []
            for _ in 0 ..< Int.random(in: 0 ... 80, using: &generator) {
                let choice = Int.random(in: 0 ..< 7, using: &generator)
                if choice == 0 || alive.isEmpty {
                    alive.append(world.spawn(Health(Int.random(in: 0 ..< 4, using: &generator))))
                    continue
                }
                let entity = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                switch choice {
                case 1: world.insert(Health(Int.random(in: 0 ..< 4, using: &generator)), into: entity)
                case 2: _ = world.remove(Health.self, from: entity)
                case 3:
                    if world.contains(Health.self, in: entity) {
                        world[Health.self, of: entity].current = Int.random(in: 0 ..< 4, using: &generator)
                    }
                case 4: world.advanceChangeTick()
                case 5: world.update(Health.self) { health, _ in health.current = (health.current + 1) % 4 }
                default:
                    world.despawn(entity)
                    alive.removeAll { $0 == entity }
                }
            }
            for value in 0 ..< 4 {
                let found: [Entity] = world.lookup(Health(value)).sorted()
                let scanned: [Entity] = world.query(Health.self).filter { $0.1.current == value }.map { $0.entity }.sorted()
                #expect(found == scanned)
            }
        }
    }

    @Test("A keyed lookup finds the entities whose property equals a value, with or without an index")
    func keyedLookup() {
        var world = World()
        let first = world.spawn(Place(set: 1, record: 10, slot: 3))
        let second = world.spawn(Place(set: 2, record: 20, slot: 3))
        world.spawn(Place(set: 1, record: 30, slot: 4))
        let slotThree: Set<Entity> = [first, second]
        let none: [Entity] = []
        #expect(Set(world.lookup(\Place.slot, equals: 3)) == slotThree)
        world.index(\Place.slot)
        #expect(Set(world.lookup(\Place.slot, equals: 3)) == slotThree)
        #expect(world.lookup(\Place.slot, equals: 9) == none)
        #expect(world.lookup(\Health.current, equals: 3) == none)
    }

    @Test("Spawning, inserting, removing and despawning keep a keyed index current")
    func keyedKeptCurrent() {
        var world = World()
        world.index(\Place.slot)
        let a = world.spawn(Place(set: 1, record: 1, slot: 5))
        let b = world.spawn(Position(x: 0, y: 0))
        world.insert(Place(set: 2, record: 2, slot: 5), into: b)
        let both: Set<Entity> = [a, b]
        #expect(Set(world.lookup(\Place.slot, equals: 5)) == both)
        world.insert(Place(set: 1, record: 1, slot: 6), into: a)
        let onlyA: [Entity] = [a]
        let onlyB: [Entity] = [b]
        #expect(world.lookup(\Place.slot, equals: 5) == onlyB)
        #expect(world.lookup(\Place.slot, equals: 6) == onlyA)
        world.insert(Place(set: 9, record: 9, slot: 6), into: a)
        #expect(world.lookup(\Place.slot, equals: 6) == onlyA)
        world.remove(Place.self, from: b)
        let none: [Entity] = []
        #expect(world.lookup(\Place.slot, equals: 5) == none)
        world.despawn(a)
        #expect(world.lookup(\Place.slot, equals: 6) == none)
    }

    @Test("A change in place is found by a keyed lookup at once, and the keyed index is rebuilt at the next tick")
    func keyedChangesInPlace() {
        var world = World()
        world.index(\Place.slot)
        let a = world.spawn(Place(set: 1, record: 1, slot: 1))
        let b = world.spawn(Place(set: 1, record: 2, slot: 2))
        world[Place.self, of: a].slot = 7
        let onlyA: [Entity] = [a]
        let onlyB: [Entity] = [b]
        let none: [Entity] = []
        #expect(world.lookup(\Place.slot, equals: 7) == onlyA)
        #expect(world.lookup(\Place.slot, equals: 1) == none)
        world.advanceChangeTick()
        #expect(world.lookup(\Place.slot, equals: 7) == onlyA)
        world.insert(Place(set: 1, record: 2, slot: 8), into: b)
        #expect(world.lookup(\Place.slot, equals: 8) == onlyB)
    }

    @Test("Indexes on two key paths and on the whole value of one type are each kept current")
    func severalIndexes() {
        var world = World()
        world.index(\Place.slot)
        world.index(\Place.set)
        world.index(Place.self)
        let a = world.spawn(Place(set: 1, record: 1, slot: 3))
        let b = world.spawn(Place(set: 2, record: 2, slot: 3))
        world.insert(Place(set: 2, record: 1, slot: 4), into: a)
        let both: Set<Entity> = [a, b]
        let onlyA: [Entity] = [a]
        let onlyB: [Entity] = [b]
        let none: [Entity] = []
        #expect(Set(world.lookup(\Place.set, equals: 2)) == both)
        #expect(world.lookup(\Place.set, equals: 1) == none)
        #expect(world.lookup(\Place.slot, equals: 3) == onlyB)
        #expect(world.lookup(\Place.slot, equals: 4) == onlyA)
        #expect(world.lookup(Place(set: 2, record: 1, slot: 4)) == onlyA)
        #expect(world.lookup(Place(set: 1, record: 1, slot: 3)) == none)
    }

    @Test("Indexing a key path twice keeps one index, and a copy keeps its own keyed index")
    func keyedTwiceAndCopies() {
        var world = World()
        world.index(\Place.slot)
        world.index(\Place.slot)
        let a = world.spawn(Place(set: 1, record: 1, slot: 1))
        let copy = world
        world.insert(Place(set: 1, record: 1, slot: 2), into: a)
        let onlyA: [Entity] = [a]
        let none: [Entity] = []
        #expect(copy.lookup(\Place.slot, equals: 1) == onlyA)
        #expect(world.lookup(\Place.slot, equals: 2) == onlyA)
        #expect(world.lookup(\Place.slot, equals: 1) == none)
    }

    @Test("Keyed lookups agree with a scan under random changes", .tags(.randomized))
    func keyedMatchesScan() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            world.index(\Place.slot)
            world.index(\Place.set)
            var alive: [Entity] = []
            func randomPlace() -> Place {
                Place(set: Int.random(in: 0 ..< 3, using: &generator), record: Int.random(in: 0 ..< 3, using: &generator), slot: Int.random(in: 0 ..< 4, using: &generator))
            }
            for _ in 0 ..< Int.random(in: 0 ... 80, using: &generator) {
                let choice = Int.random(in: 0 ..< 7, using: &generator)
                if choice == 0 || alive.isEmpty {
                    alive.append(world.spawn(randomPlace()))
                    continue
                }
                let entity = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                switch choice {
                case 1: world.insert(randomPlace(), into: entity)
                case 2: _ = world.remove(Place.self, from: entity)
                case 3:
                    if world.contains(Place.self, in: entity) {
                        world[Place.self, of: entity].slot = Int.random(in: 0 ..< 4, using: &generator)
                    }
                case 4: world.advanceChangeTick()
                case 5: world.update(Place.self) { place, _ in place.set = (place.set + 1) % 3 }
                default:
                    world.despawn(entity)
                    alive.removeAll { $0 == entity }
                }
            }
            for value in 0 ..< 4 {
                let bySlot: [Entity] = world.lookup(\Place.slot, equals: value).sorted()
                let scannedSlot: [Entity] = world.query(Place.self).filter { $0.1.slot == value }.map { $0.entity }.sorted()
                let bySet: [Entity] = world.lookup(\Place.set, equals: value).sorted()
                let scannedSet: [Entity] = world.query(Place.self).filter { $0.1.set == value }.map { $0.entity }.sorted()
                #expect(bySlot == scannedSlot)
                #expect(bySet == scannedSet)
            }
        }
    }
}
