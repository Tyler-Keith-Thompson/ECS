// Relations: pairs of a relation and a target, indexed both ways. Self-contained.

import ECSTestSupport
import Foundation
import PropertyBased
import Testing
import WorldModule

struct Likes: Relation, Hashable, Codable {}

struct Owes: Relation, Hashable, Codable {
    var amount: Int
}

struct Wields: Relation, Hashable {
    static var isExclusive: Bool { true }
}

struct PartOf: Relation, Hashable {
    static var onTargetDespawn: CleanupAction { .despawn }
}

@Suite("World: relations")
struct RelationTests {
    @Test("Relating lists targets and sources in the order they were related")
    func targetsAndSources() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        let carol = world.spawn()
        world.relate(alice, Likes(), to: bob)
        world.relate(alice, Likes(), to: carol)
        world.relate(carol, Likes(), to: bob)
        let aliceLikes: [Entity] = [bob, carol]
        let likesBob: [Entity] = [alice, carol]
        let none: [Entity] = []
        #expect(world.targets(Likes.self, of: alice) == aliceLikes)
        #expect(world.sources(Likes.self, of: bob) == likesBob)
        #expect(world.targets(Likes.self, of: bob) == none)
        #expect(world.sources(Owes.self, of: bob) == none)
    }

    @Test("Relating again replaces the pair's value; the Targets subscript reads it")
    func values() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Owes(amount: 5), to: bob)
        world.relate(alice, Owes(amount: 8), to: bob)
        let owed: Owes? = Owes(amount: 8)
        let nothing: Owes? = nil
        #expect(world[Targets<Owes>.self, of: alice][bob] == owed)
        #expect(world[Targets<Owes>.self, of: alice][alice] == nothing)
        let one: Int = 1
        #expect(world[Targets<Owes>.self, of: alice].count == one)
    }

    @Test("Relating by an exclusive relation replaces the source's target")
    func exclusive() {
        var world = World()
        let knight = world.spawn()
        let sword = world.spawn()
        let axe = world.spawn()
        world.relate(knight, Wields(), to: sword)
        world.relate(knight, Wields(), to: axe)
        let wielded: [Entity] = [axe]
        let none: [Entity] = []
        let wielder: [Entity] = [knight]
        #expect(world.targets(Wields.self, of: knight) == wielded)
        #expect(world.sources(Wields.self, of: sword) == none)
        #expect(world.sources(Wields.self, of: axe) == wielder)
    }

    @Test("Unrelating returns the value, and the last pair takes the Targets component with it")
    func unrelate() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Owes(amount: 3), to: bob)
        let removed: Owes? = Owes(amount: 3)
        let nothing: Owes? = nil
        #expect(world.unrelate(alice, Owes.self, from: bob) == removed)
        #expect(world.unrelate(alice, Owes.self, from: bob) == nothing)
        #expect(!world.contains(Targets<Owes>.self, in: alice))
        let none: [Entity] = []
        #expect(world.sources(Owes.self, of: bob) == none)
    }

    @Test("Despawning a target removes its pairs from the sources by default")
    func despawnTargetRemoves() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        let carol = world.spawn()
        world.relate(alice, Likes(), to: bob)
        world.relate(alice, Likes(), to: carol)
        world.relate(carol, Likes(), to: bob)
        world.despawn(bob)
        let aliceLikes: [Entity] = [carol]
        #expect(world.targets(Likes.self, of: alice) == aliceLikes)
        #expect(!world.contains(Targets<Likes>.self, in: carol))
        #expect(world.contains(alice))
        #expect(world.contains(carol))
    }

    @Test("Despawning a target despawns the sources of a relation that cleans up by despawning")
    func despawnTargetCascades() {
        var world = World()
        let ship = world.spawn()
        let hull = world.spawn()
        let plank = world.spawn()
        let crew = world.spawn()
        world.relate(hull, PartOf(), to: ship)
        world.relate(plank, PartOf(), to: hull)
        world.relate(crew, Likes(), to: plank)
        world.despawn(ship)
        #expect(!world.contains(hull))
        #expect(!world.contains(plank))
        #expect(world.contains(crew))
        #expect(!world.contains(Targets<Likes>.self, in: crew))
    }

    @Test("A long chain of despawning relations is despawned without recursion")
    func longCascade() {
        var world = World()
        let root = world.spawn()
        var previous = root
        for _ in 0 ..< 20_000 {
            let next = world.spawn()
            world.relate(next, PartOf(), to: previous)
            previous = next
        }
        world.despawn(root)
        let none: Int = 0
        #expect(world.count == none)
    }

    @Test("Despawning a source removes it from its targets' sources")
    func despawnSource() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Likes(), to: bob)
        world.relate(bob, Likes(), to: bob)
        world.despawn(alice)
        let selfOnly: [Entity] = [bob]
        #expect(world.sources(Likes.self, of: bob) == selfOnly)
        world.despawn(bob)
        let none: Int = 0
        #expect(world.count == none)
    }

    @Test("A stale entity has no targets and no sources, even after its slot is reused")
    func staleReads() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Likes(), to: bob)
        world.relate(bob, Likes(), to: alice)
        world.despawn(alice)
        let reused = world.spawn()
        world.relate(bob, Likes(), to: reused)
        world.relate(reused, Likes(), to: bob)
        let none: [Entity] = []
        let reusedOnly: [Entity] = [reused]
        let bobOnly: [Entity] = [bob]
        #expect(reused.index == alice.index)
        #expect(world.targets(Likes.self, of: alice) == none)
        #expect(world.sources(Likes.self, of: alice) == none)
        #expect(world.targets(Likes.self, of: reused) == bobOnly)
        #expect(world.sources(Likes.self, of: bob) == reusedOnly)
    }

    @Test("A relation by default relates a source to any number of targets and removes pairs when a target is despawned")
    func relationDefaults() {
        let isExclusive = Likes.isExclusive
        let cleanup = Likes.onTargetDespawn
        #expect(!isExclusive)
        #expect(cleanup == .remove)
    }

    @Test("Removing the Targets component directly unindexes its pairs")
    func removeTargetsComponent() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Likes(), to: bob)
        world.remove(Targets<Likes>.self, from: alice)
        let none: [Entity] = []
        #expect(world.sources(Likes.self, of: bob) == none)
    }

    @Test("A query related to a target lists that target's sources, with its other conditions")
    func relatedQuery() {
        var world = World()
        let bob = world.spawn(Name("bob"))
        let alice = world.spawn(Name("alice"))
        let carol = world.spawn(Name("carol"), Frozen())
        let dave = world.spawn(Name("dave"))
        world.relate(alice, Likes(), to: bob)
        world.relate(carol, Likes(), to: bob)
        world.relate(dave, Likes(), to: alice)
        let likers: Set<Entity> = Set(world.query(Name.self).related(Likes.self, to: bob).map { $0.entity })
        let expected: Set<Entity> = [alice, carol]
        #expect(likers == expected)
        let warm: [Entity] = world.query(Query(Name.self).related(Likes.self, to: bob).without(Frozen.self)).map { $0.entity }
        let onlyAlice: [Entity] = [alice]
        #expect(warm == onlyAlice)
        let anyLikes: Set<Entity> = Set(world.query(Query(Name.self).with(Targets<Likes>.self)).map { $0.entity })
        let allLikers: Set<Entity> = [alice, carol, dave]
        #expect(anyLikes == allLikers)
        let entitiesOnly: Set<Entity> = Set(world.query().related(Likes.self, to: bob))
        #expect(entitiesOnly == expected)
        let nobody: Int = 0
        #expect(world.query(Name.self).related(Likes.self, to: dave).count == nobody)
    }

    @Test("An update related to a target changes only that target's sources")
    func relatedUpdate() {
        var world = World()
        let bob = world.spawn(Health(0))
        let alice = world.spawn(Health(0))
        let carol = world.spawn(Health(0))
        world.relate(alice, Likes(), to: bob)
        world.update(Health.self, where: .related(Likes.self, to: bob)) { health, _ in health.current = 1 }
        let raised: Health = Health(1)
        let unchanged: Health = Health(0)
        #expect(world[Health.self, of: alice] == raised)
        #expect(world[Health.self, of: carol] == unchanged)
        #expect(world[Health.self, of: bob] == unchanged)
    }

    @Test("A query reads a source's Targets as a term")
    func targetsTerm() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Owes(amount: 2), to: bob)
        let rows: [[Entity]] = world.query(Targets<Owes>.self).map { $0.1.entities }
        let expected: [[Entity]] = [[bob]]
        #expect(rows == expected)
    }

    @Test("A clone relates to its original's targets")
    func cloning() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Likes(), to: bob)
        let twin = world.clone(alice)
        let both: [Entity] = [alice, twin]
        #expect(world.sources(Likes.self, of: bob) == both)
    }

    @Test("A copy of a world keeps its own pairs")
    func copies() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        let copy = world
        world.relate(alice, Likes(), to: bob)
        let none: [Entity] = []
        let liker: [Entity] = [alice]
        #expect(copy.sources(Likes.self, of: bob) == none)
        #expect(world.sources(Likes.self, of: bob) == liker)
    }

    @Test("Commands relate and unrelate, resolving spawned entities, and skip stale ones")
    func commands() {
        var world = World()
        let bob = world.spawn()
        let gone = world.spawn()
        world.despawn(gone)
        var commands = Commands()
        let alice = commands.spawn()
        commands.relate(alice, Likes(), to: bob)
        commands.relate(gone, Likes(), to: bob)
        let spawned = world.apply(commands)
        let liker: [Entity] = [spawned[0]]
        #expect(world.sources(Likes.self, of: bob) == liker)
        var removal = Commands()
        removal.unrelate(spawned[0], Likes.self, from: bob)
        world.apply(removal)
        let none: [Entity] = []
        #expect(world.sources(Likes.self, of: bob) == none)
    }

    @Test("The checked spellings throw StaleEntity and change nothing")
    func checkedSpellings() {
        var world = World()
        let alice = world.spawn()
        let gone = world.spawn()
        world.despawn(gone)
        #expect(throws: StaleEntity()) {
            try world.relate(alice, Likes(), checkedTo: gone)
        }
        #expect(throws: StaleEntity()) {
            try world.relate(gone, Likes(), checkedTo: alice)
        }
        #expect(throws: StaleEntity()) {
            try world.unrelate(gone, Likes.self, checkedFrom: alice)
        }
        #expect(!world.contains(Targets<Likes>.self, in: alice))
    }

    @Test("Relating a stale source traps")
    func relateStaleTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let alice = world.spawn()
            let gone = world.spawn()
            world.despawn(gone)
            world.relate(gone, Likes(), to: alice)
        }
    }

    @Test("Relating to a stale target traps")
    func relateToStaleTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let alice = world.spawn()
            let gone = world.spawn()
            world.despawn(gone)
            world.relate(alice, Likes(), to: gone)
        }
    }

    @Test("Unrelating a stale source traps")
    func unrelateStaleTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let alice = world.spawn()
            let gone = world.spawn()
            world.despawn(gone)
            world.unrelate(gone, Likes.self, from: alice)
        }
    }

    @Test("A concurrent change writing a relation's Targets brings its index back")
    func concurrentChange() {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Likes(), to: bob)
        world.runConcurrently([
            ConcurrentChange(access: .writes(Targets<Likes>.self)) { world in
                world.relate(bob, Likes(), to: alice)
                world.unrelate(alice, Likes.self, from: bob)
            },
        ])
        let none: [Entity] = []
        let liker: [Entity] = [bob]
        #expect(world.sources(Likes.self, of: bob) == none)
        #expect(world.sources(Likes.self, of: alice) == liker)
    }

    @Test("Targets encode as their entities and relations")
    func coding() throws {
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Owes(amount: 4), to: bob)
        let targets = world[Targets<Owes>.self, of: alice]
        let data = try JSONEncoder().encode(targets)
        let decoded = try JSONDecoder().decode(Targets<Owes>.self, from: data)
        #expect(decoded == targets)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        let expected: [String] = ["entities", "relations"]
        #expect(keys == expected)
    }

    @Test("Targets and sources match a model under random relating and despawning", .tags(.randomized))
    func matchesModel() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            var alive: [Entity] = (0 ..< 8).map { _ in world.spawn() }
            var model: [Entity: [Entity]] = [:]
            for _ in 0 ..< Int.random(in: 0 ... 60, using: &generator) {
                guard !alive.isEmpty else { break }
                let source = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                let target = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                switch Int.random(in: 0 ..< 4, using: &generator) {
                case 0, 1:
                    world.relate(source, Likes(), to: target)
                    if !(model[source] ?? []).contains(target) { model[source, default: []].append(target) }
                case 2:
                    world.unrelate(source, Likes.self, from: target)
                    model[source]?.removeAll { $0 == target }
                default:
                    world.despawn(target)
                    alive.removeAll { $0 == target }
                    model[target] = nil
                    for key in model.keys { model[key]?.removeAll { $0 == target } }
                }
            }
            for entity in alive {
                let targets: [Entity] = world.targets(Likes.self, of: entity)
                let expectedTargets: [Entity] = model[entity] ?? []
                #expect(targets == expectedTargets)
                let sources: [Entity] = world.sources(Likes.self, of: entity).sorted()
                let expectedSources: [Entity] = model.keys.filter { (model[$0] ?? []).contains(entity) }.sorted()
                #expect(sources == expectedSources)
                let queried: [Entity] = world.query().related(Likes.self, to: entity).sorted()
                #expect(queried == expectedSources)
            }
        }
    }
}
