// Each test is self-contained: it builds its own worlds and states its own expectations.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("World equality")
struct EqualityTests {
    @Test("Worlds with the same entities and components are equal, whatever order components were stored in")
    func storageOrder() {
        var first = World()
        let a = first.spawn(Health(1))
        let b = first.spawn(Health(2))
        var second = World()
        _ = second.spawn()
        _ = second.spawn()
        second.insert(Health(2), into: b)
        second.insert(Health(1), into: a)
        #expect(first.snapshot(Health.self) == second.snapshot(Health.self))
    }

    @Test("A different component value, a missing component or an extra entity makes worlds unequal")
    func differences() {
        var world = World()
        let entity = world.spawn(Health(1), Name("n"))
        var changed = world
        changed[Health.self, of: entity].current = 2
        var missing = world
        missing.remove(Name.self, from: entity)
        var extra = world
        extra.spawn()
        let original = world.snapshot(Health.self, Name.self)
        #expect(changed.snapshot(Health.self, Name.self) != original)
        #expect(missing.snapshot(Health.self, Name.self) != original)
        #expect(extra.snapshot(Health.self, Name.self) != original)
    }

    @Test("Types left out of the comparison are ignored")
    func leftOut() {
        var world = World()
        let entity = world.spawn(Health(1), Name("n"))
        var renamed = world
        renamed[Name.self, of: entity] = Name("other")
        #expect(world.snapshot(Health.self) == renamed.snapshot(Health.self))
        #expect(world.snapshot(Health.self, Name.self) != renamed.snapshot(Health.self, Name.self))
    }

    @Test("Worlds that would hand out different handles from later spawns are unequal")
    func allocator() {
        var first = World()
        let a = first.spawn()
        let b = first.spawn()
        var second = first
        first.despawn(a)
        first.despawn(b)
        second.despawn(b)
        second.despawn(a)
        var stale = World()
        let reused = stale.spawn()
        stale.despawn(reused)
        stale.spawn()
        var fresh = World()
        fresh.spawn()
        #expect(first.snapshot() != second.snapshot())
        #expect(stale.snapshot() != fresh.snapshot())
    }

    @Test("Worlds with different parents or children in a different order are unequal")
    func hierarchy() throws {
        var world = World()
        let parent = world.spawn()
        let first = world.spawn()
        let second = world.spawn()
        var linked = world
        try linked.addChild(first, to: parent)
        try linked.addChild(second, to: parent)
        var reordered = world
        try reordered.addChild(second, to: parent)
        try reordered.addChild(first, to: parent)
        var sameAsLinked = world
        try sameAsLinked.addChild(first, to: parent)
        try sameAsLinked.addChild(second, to: parent)
        #expect(linked.snapshot() != world.snapshot())
        #expect(linked.snapshot() != reordered.snapshot())
        #expect(linked.snapshot() == sameAsLinked.snapshot())
    }

    @Test("Empty worlds are equal")
    func empty() {
        #expect(World().snapshot(Health.self) == World().snapshot(Health.self))
    }

    @Test("Replaying the same operations gives equal worlds, and one more change makes them unequal", .tags(.randomized))
    func replay() async {
        let operations = Gen.int(in: 0 ... 1_000_000).array(of: 1 ... 200)
        await propertyCheck(count: 100, input: operations) { operations in
            func play(_ operations: [Int]) -> World {
                var world = World()
                var live: [Entity] = []
                for code in operations {
                    let argument = code / 4
                    let target = live.isEmpty ? nil : live[argument % live.count]
                    switch (code % 4, target) {
                    case (0, _), (_, nil):
                        live.append(world.spawn(Health(argument)))
                    case let (1, entity?):
                        world.insert(Name("\(argument)"), into: entity)
                    case let (2, entity?):
                        try? world.addChild(live[(argument / 3) % live.count], to: entity)
                    default:
                        world.despawn(target!)
                        live.removeAll { !world.contains($0) }
                    }
                }
                return world
            }
            var recorded = play(operations)
            let replayed = play(operations)
            #expect(recorded.snapshot(Health.self, Name.self) == replayed.snapshot(Health.self, Name.self))
            #expect(World(restoring: recorded.snapshot(Health.self, Name.self)).snapshot(Health.self, Name.self) == recorded.snapshot(Health.self, Name.self))
            recorded.spawn(Health(-1))
            #expect(recorded.snapshot(Health.self, Name.self) != replayed.snapshot(Health.self, Name.self))
        }
    }
}
