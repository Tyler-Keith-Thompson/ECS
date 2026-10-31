// Indexes of components by value. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

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
}
