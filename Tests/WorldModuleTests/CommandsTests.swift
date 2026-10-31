// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import Testing
import WorldModule

@Suite("Commands")
struct CommandsTests {
    @Test("New commands are empty, and applying them changes nothing")
    func empty() {
        var world = World()
        _ = world.spawn(Health(1))
        let commands = Commands()
        #expect(commands.isEmpty)
        #expect(commands.count == 0)
        world.apply(commands)
        #expect(world.count == 1)
    }

    @Test("Commands recorded during an update apply afterwards, in order")
    func deferredDespawn() {
        var world = World()
        let dead = world.spawn(Health(0))
        let alive = world.spawn(Health(5))
        var commands = Commands()
        world.update(Health.self) { health, row in
            if health.current <= 0 { commands.despawn(row.entity) }
        }
        #expect(world.contains(dead))
        world.apply(commands)
        #expect(!world.contains(dead))
        #expect(world.contains(alive))
    }

    @Test("Every kind of command applies")
    func everyKind() {
        var world = World()
        let target = world.spawn(Health(1), Name("t"))
        var commands = Commands()
        commands.spawn(Health(9), Frozen())
        commands.insert(Position(x: 1, y: 1), into: target)
        commands.remove(Name.self, from: target)
        commands.insert(resource: Clock(ticks: 4))
        commands.record { world in world[Health.self, of: target].current = 3 }
        #expect(commands.count == 5)
        world.apply(commands)
        let position = Position(x: 1, y: 1)
        #expect(world.count == 2)
        #expect(world.query(Health.self).with(Frozen.self).count == 1)
        #expect(world[Position.self, of: target] == position)
        #expect(!world.contains(Name.self, in: target))
        #expect(world.resources[Clock.self].ticks == 4)
        #expect(world[Health.self, of: target].current == 3)
    }

    @Test("Commands on an entity that is no longer live do nothing")
    func staleCommands() {
        var world = World()
        let entity = world.spawn(Health(1))
        var commands = Commands()
        commands.despawn(entity)
        commands.despawn(entity)
        commands.insert(Name("late"), into: entity)
        commands.remove(Health.self, from: entity)
        world.apply(commands)
        #expect(world.count == 0)
        #expect(world.count(of: Name.self) == 0)
    }

    @Test("Commands apply to any world, again and again", .tags(.copyOnWrite))
    func reusable() {
        var commands = Commands()
        commands.spawn(Health(1))
        var first = World()
        var second = World()
        first.apply(commands)
        first.apply(commands)
        second.apply(commands)
        #expect(first.count == 2)
        #expect(second.count == 1)
    }
}

@Suite("Resources")
struct ResourcesTests {
    @Test("Resources are stored by type, replaced on insert and changed in place")
    func storeAndChange() {
        var world = World()
        #expect(world.resources.isEmpty)
        world.resources.insert(Clock(ticks: 1))
        world.resources.insert(Gravity(acceleration: 9.8))
        world.resources.insert(Clock(ticks: 2))
        #expect(world.resources.count == 2)
        world.resources[Clock.self].ticks += 1
        #expect(world.resources[Clock.self].ticks == 3)
        #expect(world.resources.contains(Gravity.self))
    }

    @Test("Removing a resource returns it, and removing again returns nil")
    func remove() {
        var resources = Resources()
        resources.insert(Clock(ticks: 1))
        let removed = resources.remove(Clock.self)
        let expected = Clock(ticks: 1)
        #expect(removed == expected)
        #expect(resources.remove(Clock.self) == nil)
        #expect(!resources.contains(Clock.self))
    }

    @Test("A copy's resources are independent of the original's", .tags(.copyOnWrite))
    func valueSemantics() {
        var original = World()
        original.resources.insert(Clock(ticks: 1))
        var copy = original
        copy.resources[Clock.self].ticks = 5
        #expect(original.resources[Clock.self].ticks == 1)
        #expect(copy.resources[Clock.self].ticks == 5)
    }
}

/// A relation for the command buffer's relation tests.
struct CommandsTestRival: Relation, Hashable {}

extension CommandsTests {
    @Test("An unrelate command removes the relation, and does nothing when its source is gone by then")
    func unrelateCommand() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        let carol = world.spawn()
        world.relate(alice, CommandsTestRival(), to: bob)
        world.relate(carol, CommandsTestRival(), to: bob)
        var commands = Commands()
        commands.unrelate(alice, CommandsTestRival.self, from: bob)
        commands.despawn(carol)
        commands.unrelate(carol, CommandsTestRival.self, from: bob)
        world.apply(commands)
        let none: [Entity] = []
        #expect(world.targets(CommandsTestRival.self, of: alice) == none)
        #expect(world.sources(CommandsTestRival.self, of: bob) == none)
        #expect(world.contains(bob))
    }

    @Test("Queued buffers apply in the order queued, buffers they queue apply too, and the spawned entities return in order")
    func queuedCommands() {
        var world = World()
        var first = Commands()
        first.spawn(Name("first"))
        first.record { world in
            var nested = Commands()
            nested.spawn(Name("nested"))
            world.queue(nested)
        }
        var second = Commands()
        second.spawn(Name("second"))
        world.queue(first)
        world.queue(second)
        #expect(world.hasQueuedCommands)
        let spawned = world.applyQueuedCommands()
        #expect(!world.hasQueuedCommands)
        let names: [String] = spawned.map { world[Name.self, of: $0].text }
        let expected: [String] = ["first", "second", "nested"]
        #expect(names == expected)
        let none: [Entity] = []
        #expect(world.applyQueuedCommands() == none)
    }
}
