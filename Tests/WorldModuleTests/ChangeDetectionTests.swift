// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import Testing
import WorldModule

@Suite("World: change detection")
struct ChangeDetectionTests {
    @Test("A new world's tick is 1, and advancing it counts up")
    func ticks() {
        var world = World()
        let one = ChangeTick(1)
        let two = ChangeTick(2)
        #expect(world.changeTick == one)
        #expect(world.advanceChangeTick() == two)
        #expect(world.changeTick == two)
        #expect(ChangeTick.zero < one)
        #expect(world.lastRun == .zero)
    }

    @Test("Every component is added and changed after tick zero")
    func everythingAfterZero() {
        var world = World()
        let a = world.spawn(Health(1))
        let b = world.spawn(Health(2))
        #expect(Set(world.query().added(Health.self, since: .zero)) == [a, b])
        #expect(Set(world.query().changed(Health.self, since: .zero)) == [a, b])
    }

    @Test("Nothing is newer than the current tick until the world changes after advancing")
    func nothingNewYet() {
        var world = World()
        world.spawn(Health(1))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        #expect(world.query(Health.self).changed(Health.self, since: checkpoint).count == 0)
        #expect(world.query(Health.self).added(Health.self, since: checkpoint).count == 0)
    }

    @Test("Inserting a new component marks it added and changed; replacing marks it changed only")
    func insertMarks() {
        var world = World()
        let replaced = world.spawn(Health(1))
        let fresh = world.spawn()
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world.insert(Health(5), into: replaced)
        world.insert(Health(6), into: fresh)
        #expect(Array(world.query().added(Health.self, since: checkpoint)) == [fresh])
        #expect(Set(world.query().changed(Health.self, since: checkpoint)) == [replaced, fresh])
    }

    @Test("Writing through the subscript marks the component changed")
    func subscriptMarks() {
        var world = World()
        let hero = world.spawn(Health(10))
        _ = world.spawn(Health(10))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world[Health.self, of: hero].current -= 1
        let rows = world.query(Health.self).changed(Health.self, since: checkpoint).map(\.entity)
        #expect(rows == [hero])
    }

    @Test("Reading through the subscript or a query marks nothing")
    func readsDoNotMark() {
        var world = World()
        let hero = world.spawn(Health(10))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        _ = world[Health.self, of: hero]
        _ = try? world[checked: Health.self, of: hero]
        for _ in world.query(Health.self) {}
        #expect(world.query().changed(Health.self, since: checkpoint).count == 0)
    }

    @Test("update marks every component it visits changed, and only those")
    func updateMarks() {
        var world = World()
        let moving = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let frozen = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Frozen())
        let still = world.spawn(Position(x: 0, y: 0))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, row in
            position.x += row.components.dx
        }
        #expect(Array(world.query().changed(Position.self, since: checkpoint)) == [moving])
        #expect(world.query().changed(Velocity.self, since: checkpoint).count == 0)
        #expect(world.contains(frozen) && world.contains(still))
    }

    @Test("Two-type update marks both types changed")
    func updateTwoMarks() {
        var world = World()
        let entity = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world.update(Position.self, Velocity.self) { _, _, _ in }
        #expect(Array(world.query().changed(Position.self, since: checkpoint).changed(Velocity.self, since: checkpoint)) == [entity])
    }

    @Test("A component removed and inserted again is added again")
    func reinsertIsAdded() {
        var world = World()
        let entity = world.spawn(Health(1))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world.remove(Health.self, from: entity)
        world.insert(Health(2), into: entity)
        #expect(Array(world.query().added(Health.self, since: checkpoint)) == [entity])
    }

    @Test("A component keeps its ticks when removal elsewhere moves it in storage")
    func ticksFollowSwaps() {
        var world = World()
        let first = world.spawn(Health(1))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        let last = world.spawn(Health(2))
        world.despawn(first)
        let middle = world.spawn(Health(3))
        world.remove(Health.self, from: middle)
        #expect(Array(world.query().added(Health.self, since: checkpoint)) == [last])
        #expect(world.query().added(Health.self, since: .zero).count == 1)
    }

    @Test("Without a tick, filters compare against the world's lastRun")
    func defaultsToLastRun() {
        var world = World()
        let old = world.spawn(Health(1))
        world.lastRun = world.changeTick
        world.advanceChangeTick()
        let new = world.spawn(Health(2))
        #expect(Array(world.query().added(Health.self)) == [new])
        #expect(world.query(Health.self).changed(Health.self).map(\.entity) == [new])
        let filter = QueryFilter.changed(Health.self)
        #expect(Array(world.query().filtered(by: filter)) == [new])
        world.lastRun = .zero
        #expect(Set(world.query().changed(Health.self)) == [old, new])
    }

    @Test("Tick filters compose with with and without, and a type never stored passes nothing")
    func composes() {
        var world = World()
        _ = world.spawn(Health(1), Frozen())
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        let fresh = world.spawn(Health(2))
        let freshFrozen = world.spawn(Health(3), Frozen())
        #expect(Array(world.query().added(Health.self, since: checkpoint).without(Frozen.self)) == [fresh])
        #expect(Array(world.query().added(Health.self, since: checkpoint).with(Frozen.self)) == [freshFrozen])
        #expect(world.query().changed(Name.self, since: .zero).count == 0)
        #expect(world.query(Health.self).changed(Name.self, since: .zero).count == 0)
    }

    @Test("Commands stamp the tick at which they are applied")
    func commandsStamp() {
        var world = World()
        let entity = world.spawn()
        var commands = Commands()
        commands.insert(Health(1), into: entity)
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world.apply(commands)
        #expect(Array(world.query().added(Health.self, since: checkpoint)) == [entity])
    }

    @Test("Changes in a copy do not mark the original", .tags(.copyOnWrite))
    func copiesIndependent() {
        var original = World()
        let entity = original.spawn(Health(1))
        let checkpoint = original.changeTick
        original.advanceChangeTick()
        var copy = original
        copy[Health.self, of: entity].current = 2
        copy.update(Health.self) { health, _ in health.current += 1 }
        #expect(original.query().changed(Health.self, since: checkpoint).count == 0)
        #expect(copy.query().changed(Health.self, since: checkpoint).count == 1)
    }

    @Test("Added and changed agree with a model over random writes", .tags(.randomized), arguments: [5, 17, 2_026] as [UInt])
    func agreesWithModel(seed: UInt) {
        var generator = SeededRandomNumberGenerator(seed: seed)
        var world = World()
        var added: [Entity: ChangeTick] = [:]
        var changed: [Entity: ChangeTick] = [:]
        var live: [Entity] = []
        for _ in 0 ..< 2_000 {
            switch Int.random(in: 0 ..< 6, using: &generator) {
            case 0:
                let entity = world.spawn(First(0))
                added[entity] = world.changeTick
                changed[entity] = world.changeTick
                live.append(entity)
            case 1 where !live.isEmpty:
                let entity = live.remove(at: Int.random(in: 0 ..< live.count, using: &generator))
                world.despawn(entity)
                added[entity] = nil
                changed[entity] = nil
            case 2 where !live.isEmpty:
                let entity = live[Int.random(in: 0 ..< live.count, using: &generator)]
                world[First.self, of: entity].value += 1
                changed[entity] = world.changeTick
            case 3 where !live.isEmpty:
                let entity = live[Int.random(in: 0 ..< live.count, using: &generator)]
                world.insert(First(9), into: entity)
                changed[entity] = world.changeTick
            case 4:
                world.advanceChangeTick()
            default:
                if Bool.random(using: &generator) {
                    world.update(First.self) { first, _ in first.value += 1 }
                    for entity in live { changed[entity] = world.changeTick }
                }
            }
        }
        for since in 0 ... world.changeTick.value {
            let tick = ChangeTick(since)
            let expectedAdded = Set(added.filter { $0.value > tick }.keys)
            let expectedChanged = Set(changed.filter { $0.value > tick }.keys)
            #expect(Set(world.query().added(First.self, since: tick)) == expectedAdded)
            #expect(Set(world.query().changed(First.self, since: tick)) == expectedChanged)
        }
    }
}
