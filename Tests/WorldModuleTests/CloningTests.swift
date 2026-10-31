// Cloning entities and spawning from prefabs. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("World: cloning and prefabs")
struct CloningTests {
    @Test("A clone holds a copy of every component, independent of the original")
    func cloneCopies() {
        var world = World()
        let original = world.spawn(Position(x: 1, y: 2), Health(3), Frozen())
        let copy = world.clone(original)
        let position: Position = Position(x: 1, y: 2)
        let health: Health = Health(3)
        #expect(copy != original)
        #expect(world[Position.self, of: copy] == position)
        #expect(world[Health.self, of: copy] == health)
        #expect(world.contains(Frozen.self, in: copy))
        #expect(!world.contains(Name.self, in: copy))
        world[Health.self, of: copy].current = 9
        #expect(world[Health.self, of: original] == health)
    }

    @Test("Cloning an entity with no components spawns an empty entity")
    func cloneEmpty() {
        var world = World()
        let original = world.spawn()
        let copy = world.clone(original)
        #expect(world.contains(copy))
        let count: Int = 2
        #expect(world.count == count)
    }

    @Test("A clone's components are added now and fire add hooks")
    func cloneIsNew() {
        var world = World()
        world.resources.insert(Clock(ticks: 0))
        let original = world.spawn(Health(1))
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        world.onAdd(Health.self) { world, _ in world.resources[Clock.self].ticks += 1 }
        let copy = world.clone(original)
        let added: [Entity] = world.query(Health.self).added(Health.self, since: checkpoint).map(\.entity)
        let expected: [Entity] = [copy]
        #expect(added == expected)
        let hooks: Clock = Clock(ticks: 1)
        #expect(world.resources[Clock.self] == hooks)
    }

    @Test("A clone of a child is its sibling, and the original's children are not cloned")
    func cloneHierarchy() throws {
        var world = World()
        let parent = world.spawn(Name("parent"))
        let child = world.spawn(Name("child"))
        let grandchild = world.spawn(Name("grandchild"))
        try world.addChild(child, to: parent)
        try world.addChild(grandchild, to: child)
        let copy = world.clone(child)
        let expectedParent: Entity? = parent
        #expect(world.parent(of: copy) == expectedParent)
        let children: [Entity] = [child, copy]
        #expect(world.children(of: parent) == children)
        let none: [Entity] = []
        #expect(world.children(of: copy) == none)
    }

    @Test("A prefab is skipped by queries, and spawning from it copies all but the mark")
    func prefab() {
        var world = World()
        let goblin = world.spawn(Prefab(), Health(10), Name("goblin"))
        #expect(world.query(Health.self).count == 0)
        let first = world.spawn(from: goblin)
        let second = world.spawn(from: goblin)
        let spawned: [Entity] = [first, second]
        #expect(world.query(Health.self).map(\.entity).sorted() == spawned)
        #expect(!world.contains(Prefab.self, in: first))
        let name: Name = Name("goblin")
        #expect(world[Name.self, of: second] == name)
        #expect(world.query(Health.self).allowing(Prefab.self).count == 3)
    }

    @Test("Cloning a prefab makes another prefab")
    func clonePrefab() {
        var world = World()
        let goblin = world.spawn(Prefab(), Health(10))
        let copy = world.clone(goblin)
        #expect(world.contains(Prefab.self, in: copy))
    }

    @Test("Spawning from an entity that is not a prefab copies it")
    func spawnFromPlain() {
        var world = World()
        let plain = world.spawn(Health(4))
        let copy = world.spawn(from: plain)
        let health: Health = Health(4)
        #expect(world[Health.self, of: copy] == health)
    }

    @Test("The checked spellings throw StaleEntity for a stale entity and change nothing")
    func checked() {
        var world = World()
        let gone = world.spawn(Health(1))
        world.despawn(gone)
        let before = world.count
        #expect(throws: StaleEntity.self) { try world.clone(checked: gone) }
        #expect(throws: StaleEntity.self) { try world.spawn(checkedFrom: gone) }
        #expect(world.count == before)
    }

    @Test("Commands clone and spawn from prefabs, and later commands name the copies")
    func commands() {
        var world = World()
        let goblin = world.spawn(Prefab(), Health(10))
        var commands = Commands()
        let copy = commands.spawn(from: goblin)
        commands.insert(Name("named"), into: copy)
        let pendingClone = commands.clone(copy)
        let spawned = world.apply(commands)
        let count: Int = 2
        #expect(spawned.count == count)
        let name: Name = Name("named")
        #expect(world[Name.self, of: spawned[0]] == name)
        #expect(world[Name.self, of: spawned[1]] == name)
        #expect(!world.contains(Prefab.self, in: spawned[1]))
        _ = pendingClone
    }

    @Test("A command cloning an entity gone by then spawns an empty entity")
    func commandsStale() {
        var world = World()
        let gone = world.spawn(Health(1))
        var commands = Commands()
        commands.despawn(gone)
        commands.clone(gone)
        let spawned = world.apply(commands)
        let count: Int = 1
        #expect(spawned.count == count)
        #expect(!world.contains(Health.self, in: spawned[0]))
    }

    @Test("Cloning a stale entity traps")
    func staleTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let gone = world.spawn()
            world.despawn(gone)
            world.clone(gone)
        }
    }

    @Test("Spawning from a stale entity traps")
    func staleSpawnTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let gone = world.spawn()
            world.despawn(gone)
            world.spawn(from: gone)
        }
    }

    @Test("A clone holds the same components as its original", .tags(.randomized))
    func matchesOriginal() async {
        let masks = Gen.int(in: 0 ... 15).array(of: 1 ... 20)
        await propertyCheck(count: 200, input: masks) { masks in
            var world = World()
            for mask in masks {
                let entity = world.spawn()
                if mask & 1 != 0 { world.insert(Position(x: Double(mask), y: 0), into: entity) }
                if mask & 2 != 0 { world.insert(Health(mask), into: entity) }
                if mask & 4 != 0 { world.insert(Name("\(mask)"), into: entity) }
                if mask & 8 != 0 { world.insert(Frozen(), into: entity) }
                let copy = world.clone(entity)
                #expect(world.contains(Position.self, in: copy) == (mask & 1 != 0))
                #expect(world.contains(Health.self, in: copy) == (mask & 2 != 0))
                #expect(world.contains(Name.self, in: copy) == (mask & 4 != 0))
                #expect(world.contains(Frozen.self, in: copy) == (mask & 8 != 0))
                if mask & 2 != 0 { #expect(world[Health.self, of: copy] == world[Health.self, of: entity]) }
            }
        }
    }
}
