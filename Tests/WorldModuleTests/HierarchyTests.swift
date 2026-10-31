// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("Hierarchy")
struct HierarchyTests {
    @Test("A new entity has no parent, children, ancestors or descendants")
    func fresh() {
        var world = World()
        let entity = world.spawn()
        let none: [Entity] = []
        #expect(world.parent(of: entity) == nil)
        #expect(world.children(of: entity) == none)
        #expect(Array(world.ancestors(of: entity)) == none)
        #expect(Array(world.descendants(of: entity)) == none)
    }

    @Test("Children are listed in the order they were added, each with its parent")
    func addChildren() throws {
        var world = World()
        let parent = world.spawn()
        let first = world.spawn()
        let second = world.spawn()
        try world.addChild(first, to: parent)
        try world.addChild(second, to: parent)
        let expected = [first, second]
        #expect(world.children(of: parent) == expected)
        #expect(world.parent(of: first) == parent)
        #expect(world.parent(of: second) == parent)
    }

    @Test("Adding a child to a new parent moves it from the old one")
    func reparent() throws {
        var world = World()
        let old = world.spawn()
        let new = world.spawn()
        let child = world.spawn()
        try world.addChild(child, to: old)
        try world.addChild(child, to: new)
        let none: [Entity] = []
        let moved = [child]
        #expect(world.children(of: old) == none)
        #expect(world.children(of: new) == moved)
        #expect(world.parent(of: child) == new)
    }

    @Test("Adding a child to its own parent again moves it to the end")
    func readdMovesToEnd() throws {
        var world = World()
        let parent = world.spawn()
        let first = world.spawn()
        let second = world.spawn()
        try world.addChild(first, to: parent)
        try world.addChild(second, to: parent)
        try world.addChild(first, to: parent)
        let expected = [second, first]
        #expect(world.children(of: parent) == expected)
    }

    @Test("Removing a parent detaches the child and keeps both entities")
    func removeParent() throws {
        var world = World()
        let parent = world.spawn()
        let child = world.spawn()
        try world.addChild(child, to: parent)
        let removed = world.removeParent(of: child)
        let none: [Entity] = []
        #expect(removed == parent)
        #expect(world.parent(of: child) == nil)
        #expect(world.children(of: parent) == none)
        #expect(world.contains(parent))
        #expect(world.contains(child))
    }

    @Test("Removing the parent of an entity with none returns nil")
    func removeMissingParent() {
        var world = World()
        let entity = world.spawn()
        let removed = world.removeParent(of: entity)
        #expect(removed == nil)
    }

    @Test("Ancestors run from the parent to the root, descendants depth-first")
    func walks() throws {
        var world = World()
        let root = world.spawn()
        let a = world.spawn()
        let b = world.spawn()
        let a1 = world.spawn()
        let a2 = world.spawn()
        let a1x = world.spawn()
        try world.addChild(a, to: root)
        try world.addChild(b, to: root)
        try world.addChild(a1, to: a)
        try world.addChild(a2, to: a)
        try world.addChild(a1x, to: a1)
        let expectedAncestors = [a1, a, root]
        let expectedDescendants = [a, a1, a1x, a2, b]
        #expect(Array(world.ancestors(of: a1x)) == expectedAncestors)
        #expect(Array(world.descendants(of: root)) == expectedDescendants)
    }

    @Test("An entity cannot be its own parent")
    func selfParent() {
        var world = World()
        let entity = world.spawn()
        #expect(throws: CyclicHierarchy()) {
            try world.addChild(entity, to: entity)
        }
        #expect(world.parent(of: entity) == nil)
    }

    @Test("An entity cannot become a child of its descendant, and the world is unchanged")
    func cycle() throws {
        var world = World()
        let root = world.spawn()
        let child = world.spawn()
        let grandchild = world.spawn()
        try world.addChild(child, to: root)
        try world.addChild(grandchild, to: child)
        #expect(throws: CyclicHierarchy()) {
            try world.addChild(root, to: grandchild)
        }
        let none: [Entity] = []
        #expect(world.parent(of: root) == nil)
        #expect(world.children(of: grandchild) == none)
    }

    @Test("Despawning an entity despawns its descendants and detaches it from its parent")
    func despawnCascades() throws {
        var world = World()
        let root = world.spawn(Health(1))
        let middle = world.spawn(Health(2))
        let leaf = world.spawn(Health(3))
        let sibling = world.spawn(Health(4))
        try world.addChild(middle, to: root)
        try world.addChild(sibling, to: root)
        try world.addChild(leaf, to: middle)
        world.despawn(middle)
        let remaining = [sibling]
        #expect(!world.contains(middle))
        #expect(!world.contains(leaf))
        #expect(world.contains(root))
        #expect(world.children(of: root) == remaining)
        #expect(world.count(of: Health.self) == 2)
    }

    @Test("The checked despawn also despawns descendants")
    func checkedDespawnCascades() throws {
        var world = World()
        let root = world.spawn()
        let child = world.spawn()
        try world.addChild(child, to: root)
        try world.despawn(checked: root)
        #expect(world.isEmpty)
    }

    @Test("The hierarchy is the ChildOf relation: queries find children, entities with a parent and roots")
    func childOfQueries() throws {
        var world = World()
        let ship = world.spawn(Name("ship"))
        let turret = world.spawn(Name("turret"))
        let hull = world.spawn(Name("hull"))
        let rock = world.spawn(Name("rock"))
        try world.addChild(turret, to: ship)
        try world.addChild(hull, to: ship)
        let children: [Entity] = world.query(Name.self).related(ChildOf.self, to: ship).map { $0.entity }.sorted()
        let expectedChildren: [Entity] = [turret, hull].sorted()
        #expect(children == expectedChildren)
        let parented: [Entity] = world.query(Query(Name.self).with(Targets<ChildOf>.self)).map { $0.entity }.sorted()
        #expect(parented == expectedChildren)
        let roots: [Entity] = world.query(Query(Name.self).without(Targets<ChildOf>.self)).map { $0.entity }.sorted()
        let expectedRoots: [Entity] = [ship, rock].sorted()
        #expect(roots == expectedRoots)
        let viaRelation: [Entity] = world.sources(ChildOf.self, of: ship)
        #expect(viaRelation == world.children(of: ship))
    }

    @Test("Adding a child marks its ChildOf targets added at the current tick")
    func childOfChangeDetection() throws {
        var world = World()
        let ship = world.spawn()
        let turret = world.spawn()
        let checkpoint = world.changeTick
        world.advanceChangeTick()
        try world.addChild(turret, to: ship)
        let added: [Entity] = Array(world.query().added(Targets<ChildOf>.self, since: checkpoint))
        let expected: [Entity] = [turret]
        #expect(added == expected)
    }

    @Test("Despawning the root of a deep hierarchy despawns it all without recursion")
    func deepDespawn() throws {
        var world = World()
        var root = world.spawn()
        for _ in 0 ..< 20_000 {
            let parent = world.spawn()
            try world.addChild(root, to: parent)
            root = parent
        }
        world.despawn(root)
        let none: Int = 0
        #expect(world.count == none)
    }

    @Test("A concurrent change writing Targets<ChildOf> changes the hierarchy")
    func concurrentHierarchy() {
        var world = World()
        let ship = world.spawn()
        let turret = world.spawn()
        world.runConcurrently([
            ConcurrentChange(access: .writes(Targets<ChildOf>.self)) { world in
                try? world.addChild(turret, to: ship)
            },
        ])
        let children: [Entity] = [turret]
        #expect(world.children(of: ship) == children)
        let parent: Entity? = ship
        #expect(world.parent(of: turret) == parent)
    }

    @Test("A slot reused after a despawn starts with no hierarchy")
    func reusedSlot() throws {
        var world = World()
        let parent = world.spawn()
        let child = world.spawn()
        try world.addChild(child, to: parent)
        world.despawn(parent)
        let reusedChild = world.spawn()
        let reusedParent = world.spawn()
        let none: [Entity] = []
        #expect(world.parent(of: reusedChild) == nil)
        #expect(world.parent(of: reusedParent) == nil)
        #expect(world.children(of: reusedParent) == none)
        #expect(world.children(of: reusedChild) == none)
    }

    @Test("A stale entity reads as having no parent or children")
    func staleReads() throws {
        var world = World()
        let parent = world.spawn()
        let child = world.spawn()
        try world.addChild(child, to: parent)
        let copy = world
        world.despawn(parent)
        let none: [Entity] = []
        #expect(world.parent(of: child) == nil)
        #expect(world.children(of: parent) == none)
        #expect(Array(world.descendants(of: parent)) == none)
        #expect(Array(world.ancestors(of: child)) == none)
        #expect(copy.parent(of: child) == parent)
    }

    @Test("A copy of a world keeps its hierarchy apart from the original")
    func copies() throws {
        var world = World()
        let parent = world.spawn()
        let child = world.spawn()
        var copy = world
        try copy.addChild(child, to: parent)
        #expect(world.parent(of: child) == nil)
        #expect(copy.parent(of: child) == parent)
    }

    @Test("The checked spelling throws staleEntity for a stale child or parent and cyclicHierarchy for a cycle")
    func checkedAddChild() throws {
        var world = World()
        let parent = world.spawn()
        let child = world.spawn()
        let stale = world.spawn()
        world.despawn(stale)
        #expect(throws: HierarchyError.staleEntity) { try world.addChild(stale, checkedTo: parent) }
        #expect(throws: HierarchyError.staleEntity) { try world.addChild(child, checkedTo: stale) }
        #expect(throws: HierarchyError.cyclicHierarchy) { try world.addChild(child, checkedTo: child) }
        try world.addChild(child, checkedTo: parent)
        #expect(world.parent(of: child) == parent)
    }

    @Test("The checked removeParent throws StaleEntity for a stale child")
    func checkedRemoveParent() throws {
        var world = World()
        let parent = world.spawn()
        let child = world.spawn()
        try world.addChild(child, to: parent)
        let stale = world.spawn()
        world.despawn(stale)
        #expect(throws: StaleEntity()) { try world.removeParent(checkedOf: stale) }
        let removed = try world.removeParent(checkedOf: child)
        #expect(removed == parent)
    }

    @Test("Commands add and remove children when they apply, and skip stale entities and cycles")
    func commands() throws {
        var world = World()
        let parent = world.spawn()
        let child = world.spawn()
        let other = world.spawn()
        let stale = world.spawn()
        world.despawn(stale)
        var commands = Commands()
        commands.addChild(child, to: parent)
        commands.addChild(other, to: parent)
        commands.addChild(parent, to: child)
        commands.addChild(stale, to: parent)
        commands.removeParent(of: other)
        commands.removeParent(of: stale)
        world.apply(commands)
        let expected = [child]
        #expect(world.children(of: parent) == expected)
        #expect(world.parent(of: parent) == nil)
        #expect(world.parent(of: other) == nil)
    }

    @Test("Any sequence of hierarchy changes agrees with a parent-map model", .tags(.randomized))
    func agreesWithModel() async {
        let operations = Gen.int(in: 0 ... 1_000_000).array(of: 0 ... 300)
        await propertyCheck(count: 200, input: operations) { operations in
            Self.run(operations)
        }
    }

    @Test("Long seeded sequences of hierarchy changes agree with a parent-map model", .tags(.randomized), arguments: [1, 2, 3, 42, 1_000] as [UInt])
    func seeded(seed: UInt) {
        var generator = SeededRandomNumberGenerator(seed: seed)
        let operations = (0 ..< 3_000).map { _ in Int.random(in: 0 ... 1_000_000, using: &generator) }
        Self.run(operations)
    }

    /// Replays `operations` on a world and on a naive model: a map from each live entity to its
    /// parent, with children found by scanning and kept in the order they were attached.
    static func run(_ operations: [Int]) {
        var world = World()
        var live: [Entity] = []
        var parents: [Entity: Entity] = [:]
        var attachOrder: [Entity: Int] = [:]
        var clock = 0
        func modelChildren(of entity: Entity) -> [Entity] {
            parents.filter { $0.value == entity }.map(\.key).sorted { attachOrder[$0]! < attachOrder[$1]! }
        }
        func isAncestor(_ ancestor: Entity, ofOrIs entity: Entity) -> Bool {
            var current: Entity? = entity
            while let walking = current {
                if walking == ancestor { return true }
                current = parents[walking]
            }
            return false
        }
        for code in operations {
            let kind = code % 4
            let argument = code / 4
            if kind == 0 || live.count < 2 {
                live.append(world.spawn())
                continue
            }
            let a = live[argument % live.count]
            let b = live[(argument / 7) % live.count]
            switch kind {
            case 1:
                let expectCycle = isAncestor(a, ofOrIs: b)
                do throws(CyclicHierarchy) {
                    try world.addChild(a, to: b)
                    #expect(!expectCycle)
                    parents[a] = b
                    clock += 1
                    attachOrder[a] = clock
                } catch {
                    #expect(expectCycle)
                }
            case 2:
                let removed = world.removeParent(of: a)
                #expect(removed == parents[a])
                parents[a] = nil
            default:
                var doomed: Set<Entity> = [a]
                var changed = true
                while changed {
                    changed = false
                    for (child, parent) in parents where doomed.contains(parent) && !doomed.contains(child) {
                        doomed.insert(child)
                        changed = true
                    }
                }
                world.despawn(a)
                live.removeAll { doomed.contains($0) }
                for entity in doomed { parents[entity] = nil }
                #expect(live.allSatisfy { world.contains($0) })
                #expect(doomed.allSatisfy { !world.contains($0) })
            }
            #expect(world.count == live.count)
            for entity in live {
                #expect(world.parent(of: entity) == parents[entity])
                #expect(world.children(of: entity) == modelChildren(of: entity))
            }
        }
    }
}
