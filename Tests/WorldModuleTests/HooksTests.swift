// Each test is self-contained: it builds its own world, registers its own hooks and states its
// own expectations.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

/// What hooks saw, in the order they ran.
struct HookLog: Resource {
    var entries: [String] = []
}

@Suite("Hooks")
struct HooksTests {
    @Test("Add hooks run for new components, insert hooks for new and replaced ones")
    func addAndInsert() {
        var world = World()
        world.resources.insert(HookLog())
        world.onAdd(Health.self) { world, entity in world.resources[HookLog.self].entries.append("add \(world[Health.self, of: entity].current)") }
        world.onInsert(Health.self) { world, entity in world.resources[HookLog.self].entries.append("insert \(world[Health.self, of: entity].current)") }
        let entity = world.spawn(Health(1))
        world.insert(Health(2), into: entity)
        let entries = world.resources[HookLog.self].entries
        let expected = ["add 1", "insert 1", "insert 2"]
        #expect(entries == expected)
    }

    @Test("Remove hooks get the removed component after it is gone")
    func remove() {
        var world = World()
        world.resources.insert(HookLog())
        world.onRemove(Health.self) { world, entity, health in
            let stillHeld = world.contains(Health.self, in: entity)
            world.resources[HookLog.self].entries.append("remove \(health.current) \(stillHeld)")
        }
        let entity = world.spawn(Health(7))
        let removed = world.remove(Health.self, from: entity)
        let missing = world.remove(Health.self, from: entity)
        let entries = world.resources[HookLog.self].entries
        let expected = ["remove 7 false"]
        #expect(removed == Health(7))
        #expect(missing == nil)
        #expect(entries == expected)
    }

    @Test("Despawning runs the remove hooks of every hooked component, descendants included, after the entities are gone")
    func despawn() throws {
        var world = World()
        world.resources.insert(HookLog())
        world.onRemove(Health.self) { world, entity, health in
            world.resources[HookLog.self].entries.append("health \(health.current) \(world.contains(entity))")
        }
        world.onRemove(Name.self) { world, _, name in
            world.resources[HookLog.self].entries.append("name \(name.text)")
        }
        let parent = world.spawn(Health(1), Name("parent"))
        let child = world.spawn(Health(2))
        try world.addChild(child, to: parent)
        world.despawn(parent)
        let entries = world.resources[HookLog.self].entries
        let expected = ["health 1 false", "name parent", "health 2 false"]
        #expect(entries == expected)
    }

    @Test("Hooks run after the whole spawn, so they see every component it gave")
    func afterWholeSpawn() {
        var world = World()
        world.resources.insert(HookLog())
        world.onAdd(Health.self) { world, entity in
            world.resources[HookLog.self].entries.append("name present \(world.contains(Name.self, in: entity))")
        }
        world.spawn(Health(1), Name("a"))
        world.spawn(Health(1), Name("b"), Frozen())
        world.spawn(Health(1), Name("c"), Frozen(), Velocity(dx: 0, dy: 0))
        let entries = world.resources[HookLog.self].entries
        let expected = ["name present true", "name present true", "name present true"]
        #expect(entries == expected)
    }

    @Test("Hooks fired by a hook run after the hooks already waiting")
    func nestedOrder() {
        var world = World()
        world.resources.insert(HookLog())
        world.onAdd(Health.self) { world, entity in
            world.resources[HookLog.self].entries.append("health")
            world.insert(Name("from hook"), into: entity)
        }
        world.onAdd(Name.self) { world, _ in world.resources[HookLog.self].entries.append("name") }
        world.onAdd(Frozen.self) { world, _ in world.resources[HookLog.self].entries.append("frozen") }
        let entity = world.spawn(Health(1), Frozen())
        let entries = world.resources[HookLog.self].entries
        let expected = ["health", "frozen", "name"]
        #expect(entries == expected)
        #expect(world[Name.self, of: entity] == Name("from hook"))
    }

    @Test("Several hooks of one kind run in the order they were registered")
    func registrationOrder() {
        var world = World()
        world.resources.insert(HookLog())
        world.onAdd(Health.self) { world, _ in world.resources[HookLog.self].entries.append("first") }
        world.onAdd(Health.self) { world, _ in world.resources[HookLog.self].entries.append("second") }
        world.spawn(Health(1))
        let entries = world.resources[HookLog.self].entries
        let expected = ["first", "second"]
        #expect(entries == expected)
    }

    @Test("Changes in place run no hooks")
    func inPlace() {
        var world = World()
        world.resources.insert(HookLog())
        let entity = world.spawn(Health(1))
        world.onInsert(Health.self) { world, _ in world.resources[HookLog.self].entries.append("insert") }
        world[Health.self, of: entity].current = 2
        world.update(Health.self) { health, _ in health.current += 1 }
        let entries = world.resources[HookLog.self].entries
        let expected: [String] = []
        #expect(entries == expected)
    }

    @Test("Bundles fire hooks for each component they add or remove")
    func bundles() {
        struct Pair: Bundle {
            var body: some Bundle {
                Health(1)
                Name("pair")
            }
        }
        var world = World()
        world.resources.insert(HookLog())
        world.onAdd(Name.self) { world, _ in world.resources[HookLog.self].entries.append("add name") }
        world.onRemove(Health.self) { world, _, _ in world.resources[HookLog.self].entries.append("remove health") }
        let entity = world.spawn(Pair())
        world.remove(Pair.self, from: entity)
        let entries = world.resources[HookLog.self].entries
        let expected = ["add name", "remove health"]
        #expect(entries == expected)
    }

    @Test("Removing a type's hooks stops them and leaves other types' hooks")
    func removeHooks() {
        var world = World()
        world.resources.insert(HookLog())
        world.onAdd(Health.self) { world, _ in world.resources[HookLog.self].entries.append("health") }
        world.onAdd(Name.self) { world, _ in world.resources[HookLog.self].entries.append("name") }
        world.removeHooks(of: Health.self)
        world.removeHooks(of: Frozen.self)
        world.spawn(Health(1), Name("n"))
        let entries = world.resources[HookLog.self].entries
        let expected = ["name"]
        #expect(entries == expected)
    }

    @Test("For a new component the add hooks run before the insert hooks, whichever was registered first")
    func addBeforeInsert() {
        var world = World()
        world.resources.insert(HookLog())
        world.onInsert(Health.self) { world, _ in world.resources[HookLog.self].entries.append("insert") }
        world.onAdd(Health.self) { world, _ in world.resources[HookLog.self].entries.append("add") }
        world.spawn(Health(1))
        let entries = world.resources[HookLog.self].entries
        let expected = ["add", "insert"]
        #expect(entries == expected)
    }

    @Test("Removing a type's hooks removes its add, insert and remove hooks")
    func removeHooksOfEveryKind() {
        var world = World()
        world.resources.insert(HookLog())
        world.onAdd(Health.self) { world, _ in world.resources[HookLog.self].entries.append("add") }
        world.onInsert(Health.self) { world, _ in world.resources[HookLog.self].entries.append("insert") }
        world.onRemove(Health.self) { world, _, _ in world.resources[HookLog.self].entries.append("remove") }
        world.removeHooks(of: Health.self)
        let entity = world.spawn(Health(1))
        world.insert(Health(2), into: entity)
        world.remove(Health.self, from: entity)
        world.insert(Health(3), into: entity)
        world.despawn(entity)
        let entries = world.resources[HookLog.self].entries
        let none: [String] = []
        #expect(entries == none)
    }

    @Test("Commands and checked spellings fire hooks when they apply")
    func commandsAndChecked() throws {
        var world = World()
        world.resources.insert(HookLog())
        world.onAdd(Health.self) { world, _ in world.resources[HookLog.self].entries.append("add") }
        world.onRemove(Health.self) { world, _, _ in world.resources[HookLog.self].entries.append("remove") }
        var commands = Commands()
        let spawned = commands.spawn(Health(1))
        commands.remove(Health.self, from: spawned)
        world.apply(commands)
        let entity = world.spawn()
        try world.insert(Health(2), checkedInto: entity)
        _ = try world.remove(Health.self, checkedFrom: entity)
        try world.insert(Health(3), checkedInto: entity)
        try world.despawn(checked: entity)
        let entries = world.resources[HookLog.self].entries
        let expected = ["add", "remove", "add", "remove", "add", "remove"]
        #expect(entries == expected)
    }

    @Test("A copy of a world keeps its hooks, and hooks registered on the copy stay there")
    func copies() {
        var world = World()
        world.resources.insert(HookLog())
        world.onAdd(Health.self) { world, _ in world.resources[HookLog.self].entries.append("health") }
        var copy = world
        copy.onAdd(Name.self) { world, _ in world.resources[HookLog.self].entries.append("name") }
        copy.spawn(Health(1), Name("c"))
        world.spawn(Health(1), Name("w"))
        let copyEntries = copy.resources[HookLog.self].entries
        let worldEntries = world.resources[HookLog.self].entries
        let expectedCopy = ["health", "name"]
        let expectedWorld = ["health"]
        #expect(copyEntries == expectedCopy)
        #expect(worldEntries == expectedWorld)
    }

    /// The number of `Health` components, kept by hooks.
    struct HealthCount: Resource { var count = 0 }

    @Test("Hooks keep an index that agrees with the world through any sequence of operations", .tags(.randomized))
    func indexAgrees() async {
        let operations = Gen.int(in: 0 ... 1_000_000).array(of: 0 ... 200)
        await propertyCheck(count: 200, input: operations) { operations in
            Self.run(operations)
        }
    }

    @Test("Hooks keep an index through long seeded sequences", .tags(.randomized), arguments: [1, 2, 3, 42, 1_000] as [UInt])
    func seeded(seed: UInt) {
        var generator = SeededRandomNumberGenerator(seed: seed)
        let operations = (0 ..< 3_000).map { _ in Int.random(in: 0 ... 1_000_000, using: &generator) }
        Self.run(operations)
    }

    static func run(_ operations: [Int]) {
        var world = World()
        world.resources.insert(HealthCount())
        world.onAdd(Health.self) { world, _ in world.resources[HealthCount.self].count += 1 }
        world.onRemove(Health.self) { world, _, _ in world.resources[HealthCount.self].count -= 1 }
        var live: [Entity] = []
        for code in operations {
            let argument = code / 6
            let target = live.isEmpty ? nil : live[argument % live.count]
            switch (code % 6, target) {
            case (0, _), (_, nil):
                live.append(argument.isMultiple(of: 2) ? world.spawn(Health(argument)) : world.spawn(Name("n")))
            case let (1, entity?):
                world.insert(Health(argument), into: entity)
            case let (2, entity?):
                world.remove(Health.self, from: entity)
            case let (3, entity?):
                let other = live[(argument / 7) % live.count]
                if other != entity { try? world.addChild(other, to: entity) }
            default:
                let entity = target!
                world.despawn(entity)
                live.removeAll { !world.contains($0) }
            }
            #expect(world.resources[HealthCount.self].count == world.count(of: Health.self))
        }
    }
}
