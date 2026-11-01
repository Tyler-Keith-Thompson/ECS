// Logging a component type's changes, so finding what changed costs time in proportion to the
// changes. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("World: tracking changes")
struct ChangeTrackingTests {
    @Test("A tracked type's changed filter finds writes through the subscript and through insert")
    func singleWrites() {
        var world = World()
        let a = world.spawn(Health(1))
        let b = world.spawn(Health(2))
        world.spawn(Health(3))
        world.trackChanges(of: Health.self)
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world[Health.self, of: a].current = 10
        world.insert(Health(20), into: b)
        let expected: Set<Entity> = [a, b]
        let found = Set(world.query(Health.self).changed(Health.self, since: checkpoint).map(\.entity))
        #expect(found == expected)
    }

    @Test("A tracked type's added filter finds spawned and inserted components but not changed ones")
    func added() {
        var world = World()
        let old = world.spawn(Health(1))
        let bare = world.spawn(Name("bare"))
        world.trackChanges(of: Health.self)
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        let spawned = world.spawn(Health(2))
        world.insert(Health(3), into: bare)
        world[Health.self, of: old].current = 5
        let expected: Set<Entity> = [spawned, bare]
        let found = Set(world.query(Health.self).added(Health.self, since: checkpoint).map(\.entity))
        #expect(found == expected)
    }

    @Test("Updates of one, two and three types log every entity they visit")
    func updates() {
        var world = World()
        let moving = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1), Health(1))
        let still = world.spawn(Position(x: 0, y: 0), Health(1))
        world.trackChanges(of: Position.self)
        world.trackChanges(of: Velocity.self)
        world.trackChanges(of: Health.self)
        let first = world.changeTick
        world.advanceChangeTick()
        world.update(Position.self, reading: Velocity.self) { position, row in position.x += row.components.dx }
        let onlyMoving: [Entity] = [moving]
        #expect(world.query(Position.self).changed(Position.self, since: first).map(\.entity) == onlyMoving)
        let second = world.changeTick
        world.advanceChangeTick()
        world.update(Position.self, Velocity.self) { position, velocity, _ in velocity.dx += position.x }
        #expect(world.query(Velocity.self).changed(Velocity.self, since: second).map(\.entity) == onlyMoving)
        let third = world.changeTick
        world.advanceChangeTick()
        world.update(Position.self, Velocity.self, Health.self) { _, _, health, _ in health.current += 1 }
        #expect(world.query(Health.self).changed(Health.self, since: third).map(\.entity) == onlyMoving)
        let both: Set<Entity> = [moving, still]
        #expect(Set(world.query(Health.self).changed(Health.self, since: ChangeTick.zero).map(\.entity)) == both)
    }

    @Test("A parallel update and a mutable span log the entities they change")
    func bulkWrites() {
        var world = World()
        var entities: [Entity] = []
        for index in 0 ..< 10 { entities.append(world.spawn(Health(index))) }
        world.trackChanges(of: Health.self)
        let first = world.changeTick
        world.advanceChangeTick()
        world.parallelUpdate(Health.self, minimumChunk: 2) { health, _ in health.current += 1 }
        let all = Set(entities)
        #expect(Set(world.query(Health.self).changed(Health.self, since: first).map(\.entity)) == all)
        let second = world.changeTick
        world.advanceChangeTick()
        world.withMutableSpan(of: Health.self) { _, health in health[0].current = 0 }
        #expect(Set(world.query(Health.self).changed(Health.self, since: second).map(\.entity)) == all)
    }

    @Test("Only the changes after the given tick are found, each entity once")
    func sinceTick() {
        var world = World()
        let a = world.spawn(Health(1))
        let b = world.spawn(Health(1))
        world.trackChanges(of: Health.self)
        let start = world.changeTick
        world.advanceChangeTick()
        world[Health.self, of: a].current = 2
        world[Health.self, of: a].current = 3
        let middle = world.changeTick
        world.advanceChangeTick()
        world[Health.self, of: b].current = 2
        world[Health.self, of: a].current = 4
        let fromStart = world.query(Health.self).changed(Health.self, since: start).map(\.entity)
        let fromMiddle = Set(world.query(Health.self).changed(Health.self, since: middle).map(\.entity))
        let bothOnce: [Entity] = [a, b]
        let both: Set<Entity> = [a, b]
        #expect(fromStart.sorted() == bothOnce)
        #expect(fromMiddle == both)
        let end = world.changeTick
        let none: [Entity] = []
        #expect(world.query(Health.self).changed(Health.self, since: end).map(\.entity) == none)
    }

    @Test("Entities that lost the component or were despawned after changing aren't found")
    func removals() {
        var world = World()
        let removed = world.spawn(Health(1))
        let despawned = world.spawn(Health(1))
        let kept = world.spawn(Health(1))
        world.trackChanges(of: Health.self)
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        for entity in [removed, despawned, kept] { world[Health.self, of: entity].current = 2 }
        _ = world.remove(Health.self, from: removed)
        world.despawn(despawned)
        let onlyKept: [Entity] = [kept]
        #expect(world.query(Health.self).changed(Health.self, since: checkpoint).map(\.entity) == onlyKept)
    }

    @Test("Tracking twice, tracking an unstored type, and a copy that keeps its own log")
    func twiceUnstoredAndCopies() {
        var world = World()
        world.trackChanges(of: Health.self)
        world.trackChanges(of: Health.self)
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        let a = world.spawn(Health(1))
        var copy = world
        let b = copy.spawn(Health(1))
        let original: [Entity] = [a]
        let copied: Set<Entity> = [a, b]
        #expect(world.query(Health.self).changed(Health.self, since: checkpoint).map(\.entity) == original)
        #expect(Set(copy.query(Health.self).changed(Health.self, since: checkpoint).map(\.entity)) == copied)
    }

    @Test("Many writes to few entities keep the answers right as the log compacts")
    func compaction() {
        var world = World()
        let a = world.spawn(Health(0))
        let b = world.spawn(Health(0))
        world.trackChanges(of: Health.self)
        var lastTickOfB = world.changeTick
        for round in 0 ..< 500 {
            world.advanceChangeTick()
            world[Health.self, of: a].current = round
            if round.isMultiple(of: 100) {
                lastTickOfB = world.changeTick
                world[Health.self, of: b].current = round
            }
        }
        let beforeLastOfB = ChangeTick(lastTickOfB.value - 1)
        let both: Set<Entity> = [a, b]
        let onlyA: [Entity] = [a]
        #expect(Set(world.query(Health.self).changed(Health.self, since: beforeLastOfB).map(\.entity)) == both)
        #expect(world.query(Health.self).changed(Health.self, since: lastTickOfB).map(\.entity) == onlyA)
    }

    @Test("Changed and added filters agree with and without tracking under random changes", .tags(.randomized))
    func matchesUntracked() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var tracked = World()
            tracked.trackChanges(of: Health.self)
            var untracked = World()
            var alive: [Entity] = []
            var checkpoints: [ChangeTick] = [tracked.changeTick]
            for _ in 0 ..< Int.random(in: 0 ... 200, using: &generator) {
                let choice = Int.random(in: 0 ..< 8, using: &generator)
                if choice == 0 || alive.isEmpty {
                    let value = Int.random(in: 0 ..< 5, using: &generator)
                    let entity = tracked.spawn(Health(value))
                    untracked.spawn(Health(value))
                    alive.append(entity)
                    continue
                }
                let entity = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                switch choice {
                case 1:
                    tracked.insert(Health(1), into: entity)
                    untracked.insert(Health(1), into: entity)
                case 2:
                    _ = tracked.remove(Health.self, from: entity)
                    _ = untracked.remove(Health.self, from: entity)
                case 3:
                    if tracked.contains(Health.self, in: entity) {
                        tracked[Health.self, of: entity].current += 1
                        untracked[Health.self, of: entity].current += 1
                    }
                case 4:
                    checkpoints.append(tracked.changeTick)
                    tracked.advanceChangeTick()
                    untracked.advanceChangeTick()
                case 5:
                    let threshold = Int.random(in: 0 ..< 5, using: &generator)
                    tracked.update(Health.self) { health, _ in if health.current > threshold { health.current -= 1 } }
                    untracked.update(Health.self) { health, _ in if health.current > threshold { health.current -= 1 } }
                case 6:
                    tracked.despawn(entity)
                    untracked.despawn(entity)
                    alive.removeAll { $0 == entity }
                default:
                    let healthy = tracked.query(Health.self).changed(Health.self, since: checkpoints.last).map(\.entity)
                    for entity in healthy { tracked[Health.self, of: entity].current += 0 }
                    for entity in healthy { untracked[Health.self, of: entity].current += 0 }
                }
            }
            for checkpoint in checkpoints {
                let trackedChanged = Set(tracked.query(Health.self).changed(Health.self, since: checkpoint).map(\.entity))
                let untrackedChanged = Set(untracked.query(Health.self).changed(Health.self, since: checkpoint).map(\.entity))
                let trackedAdded = Set(tracked.query(Health.self).added(Health.self, since: checkpoint).map(\.entity))
                let untrackedAdded = Set(untracked.query(Health.self).added(Health.self, since: checkpoint).map(\.entity))
                #expect(trackedChanged == untrackedChanged)
                #expect(trackedAdded == untrackedAdded)
            }
        }
    }
}
