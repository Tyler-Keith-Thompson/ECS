// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import Testing
import WorldModule

/// A bundle of fixed components.
struct Mover: Bundle {
    var position: Position

    var body: some Bundle {
        position
        Velocity(dx: 1, dy: 0)
    }
}

/// A bundle with a nested bundle, an `if` and an `if`–`else`.
struct Soldier: Bundle {
    var name: String
    var armored: Bool
    var frozen: Bool

    var body: some Bundle {
        Mover(position: Position(x: 0, y: 0))
        Name(name)
        if armored {
            Health(20)
        }
        if frozen {
            Frozen()
        } else {
            First(1)
        }
    }
}

/// A bundle that lists one type twice.
struct Repeated: Bundle {
    var body: some Bundle {
        Health(1)
        Health(2)
    }
}

/// A bundle with no components.
struct Nothing: Bundle {
    var body: some Bundle {}
}

@Suite("Bundles")
struct BundleTests {
    @Test("Spawning a bundle gives the entity every component in its body")
    func spawn() {
        var world = World()
        let entity = world.spawn(Mover(position: Position(x: 3, y: 4)))
        #expect(world[Position.self, of: entity] == Position(x: 3, y: 4))
        #expect(world[Velocity.self, of: entity] == Velocity(dx: 1, dy: 0))
    }

    @Test("Nested bundles, ifs and if-elses insert the components their conditions choose")
    func conditions() {
        var world = World()
        let armored = world.spawn(Soldier(name: "a", armored: true, frozen: true))
        let plain = world.spawn(Soldier(name: "p", armored: false, frozen: false))
        #expect(world[Name.self, of: armored] == Name("a"))
        #expect(world[Health.self, of: armored] == Health(20))
        #expect(world.contains(Frozen.self, in: armored))
        #expect(!world.contains(First.self, in: armored))
        #expect(world.contains(Velocity.self, in: plain))
        #expect(!world.contains(Health.self, in: plain))
        #expect(!world.contains(Frozen.self, in: plain))
        #expect(world.contains(First.self, in: plain))
    }

    @Test("A later component of one type in a body replaces an earlier one")
    func laterWins() {
        var world = World()
        let entity = world.spawn(Repeated())
        #expect(world[Health.self, of: entity] == Health(2))
    }

    @Test("An empty bundle spawns an entity with no components")
    func empty() {
        var world = World()
        let entity = world.spawn(Nothing())
        #expect(world.contains(entity))
        #expect(world.count(of: Health.self) == 0)
    }

    @Test("Inserting a bundle replaces the components the entity holds of its types")
    func insert() {
        var world = World()
        let entity = world.spawn(Position(x: 9, y: 9), Health(5))
        world.insert(Mover(position: Position(x: 1, y: 1)), into: entity)
        #expect(world[Position.self, of: entity] == Position(x: 1, y: 1))
        #expect(world[Velocity.self, of: entity] == Velocity(dx: 1, dy: 0))
        #expect(world[Health.self, of: entity] == Health(5))
    }

    @Test("Removing a bundle takes away every type it can hold, including both sides of an if-else, and keeps the rest")
    func remove() {
        var world = World()
        let entity = world.spawn(Soldier(name: "s", armored: false, frozen: true))
        world.insert(Second(2), into: entity)
        world.remove(Soldier.self, from: entity)
        #expect(!world.contains(Position.self, in: entity))
        #expect(!world.contains(Velocity.self, in: entity))
        #expect(!world.contains(Name.self, in: entity))
        #expect(!world.contains(Frozen.self, in: entity))
        #expect(world.contains(Second.self, in: entity))
        #expect(world.contains(entity))
    }

    @Test("A component is a bundle of itself")
    func componentIsBundle() {
        func spawnBundle(_ bundle: some Bundle, in world: inout World) -> Entity {
            world.spawn(bundle)
        }
        var world = World()
        let entity = spawnBundle(Health(3), in: &world)
        #expect(world[Health.self, of: entity] == Health(3))
        world.remove(Health.self, from: entity)
        #expect(!world.contains(Health.self, in: entity))
    }

    @Test("The checked spellings throw StaleEntity for a stale entity and change nothing")
    func checked() throws {
        var world = World()
        let stale = world.spawn()
        world.despawn(stale)
        #expect(throws: StaleEntity()) { try world.insert(Mover(position: Position(x: 0, y: 0)), checkedInto: stale) }
        #expect(throws: StaleEntity()) { try world.remove(Mover.self, checkedFrom: stale) }
        #expect(world.count(of: Position.self) == 0)
        let live = world.spawn()
        try world.insert(Mover(position: Position(x: 0, y: 0)), checkedInto: live)
        try world.remove(Mover.self, checkedFrom: live)
        #expect(!world.contains(Velocity.self, in: live))
    }

    @Test("Commands spawn, insert and remove bundles, naming spawned handles")
    func commands() {
        var world = World()
        var commands = Commands()
        let soldier = commands.spawn(Soldier(name: "c", armored: true, frozen: false))
        commands.insert(Mover(position: Position(x: 5, y: 5)), into: soldier)
        let mover = commands.spawn(Mover(position: Position(x: 0, y: 0)))
        commands.remove(Mover.self, from: mover)
        let spawned = world.apply(commands)
        #expect(world[Position.self, of: spawned[0]] == Position(x: 5, y: 5))
        #expect(world[Health.self, of: spawned[0]] == Health(20))
        #expect(!world.contains(Position.self, in: spawned[1]))
    }
}
