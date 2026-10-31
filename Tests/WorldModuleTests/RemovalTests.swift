// Removal detection: the entities that lost a component, per reader. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

enum FirstMourner {}
enum SecondMourner {}

@Suite("World: removal detection")
struct RemovalTests {
    @Test("Nothing is removed before tracking starts, and the first look starts it")
    func firstLookStarts() {
        var world = World()
        let early = world.spawn(Health(1))
        world.remove(Health.self, from: early)
        #expect(world.removed(Health.self, by: FirstMourner.self).isEmpty)
        let late = world.spawn(Health(1))
        world.remove(Health.self, from: late)
        let expected: [Entity] = [late]
        #expect(world.removed(Health.self, by: FirstMourner.self) == expected)
    }

    @Test("Removing, removing a bundle and despawning all record a removal")
    func everyKindOfRemoval() {
        var world = World()
        world.trackRemovals(of: Health.self)
        let removed = world.spawn(Health(1))
        let bundled = world.spawn(Health(1), Name("bundled"))
        let despawned = world.spawn(Health(1))
        let untouched = world.spawn(Health(1))
        world.remove(Health.self, from: removed)
        world.remove(TupleBundle<Health, Name>.self, from: bundled)
        world.despawn(despawned)
        let expected: [Entity] = [removed, bundled, despawned]
        #expect(world.removed(Health.self, by: FirstMourner.self) == expected)
        #expect(world.contains(Health.self, in: untouched))
    }

    @Test("Each reader sees each removal once")
    func perReader() {
        var world = World()
        world.trackRemovals(of: Health.self)
        let first = world.spawn(Health(1))
        world.remove(Health.self, from: first)
        let expectedFirst: [Entity] = [first]
        #expect(world.removed(Health.self, by: FirstMourner.self) == expectedFirst)
        #expect(world.removed(Health.self, by: FirstMourner.self).isEmpty)
        let second = world.spawn(Health(1))
        world.remove(Health.self, from: second)
        let both: [Entity] = [first, second]
        let onlySecond: [Entity] = [second]
        #expect(world.removed(Health.self, by: SecondMourner.self) == both)
        #expect(world.removed(Health.self, by: FirstMourner.self) == onlySecond)
    }

    @Test("Removing a component the entity does not hold records nothing")
    func absentComponent() {
        var world = World()
        world.trackRemovals(of: Health.self)
        let entity = world.spawn(Name("none"))
        world.remove(Health.self, from: entity)
        #expect(world.removed(Health.self, by: FirstMourner.self).isEmpty)
    }

    @Test("Tracking twice records each removal once")
    func idempotent() {
        var world = World()
        world.trackRemovals(of: Health.self)
        world.trackRemovals(of: Health.self)
        let entity = world.spawn(Health(1))
        world.remove(Health.self, from: entity)
        let expected: [Entity] = [entity]
        #expect(world.removed(Health.self, by: FirstMourner.self) == expected)
    }

    @Test("Removals are kept as events are: two updates drop them")
    func keptAsEvents() {
        var world = World()
        world.trackRemovals(of: Health.self)
        let entity = world.spawn(Health(1))
        world.remove(Health.self, from: entity)
        world.updateEvents()
        let kept: [Entity] = [entity]
        #expect(world.removed(Health.self, by: FirstMourner.self) == kept)
        world.updateEvents()
        #expect(world.removed(Health.self, by: SecondMourner.self).isEmpty)
    }

    @Test("Commands record removals when they apply")
    func commands() {
        var world = World()
        world.trackRemovals(of: Health.self)
        let entity = world.spawn(Health(1))
        var commands = Commands()
        commands.despawn(entity)
        world.apply(commands)
        let expected: [Entity] = [entity]
        #expect(world.removed(Health.self, by: FirstMourner.self) == expected)
    }

    @Test("Removals match a model of random removals and despawns", .tags(.randomized))
    func matchesModel() async {
        // Each step: 0 spawn with Health, 1 remove Health from an entity, 2 despawn an entity,
        // 3 reinsert Health into an entity; the second number picks the entity.
        let steps = Gen.int(in: 0 ... 3).array(of: 2 ... 2).array(of: 0 ... 40)
        await propertyCheck(count: 200, input: steps) { steps in
            var world = World()
            world.trackRemovals(of: Health.self)
            var live: [Entity] = []
            var expected: [Entity] = []
            for step in steps {
                switch step[0] {
                case 0:
                    live.append(world.spawn(Health(1)))
                case 1 where !live.isEmpty:
                    let entity = live[step[1] % live.count]
                    if world.contains(Health.self, in: entity) { expected.append(entity) }
                    world.remove(Health.self, from: entity)
                case 2 where !live.isEmpty:
                    let entity = live.remove(at: step[1] % live.count)
                    if world.contains(Health.self, in: entity) { expected.append(entity) }
                    world.despawn(entity)
                case 3 where !live.isEmpty:
                    world.insert(Health(2), into: live[step[1] % live.count])
                default:
                    break
                }
            }
            #expect(world.removed(Health.self, by: FirstMourner.self) == expected)
        }
    }
}
