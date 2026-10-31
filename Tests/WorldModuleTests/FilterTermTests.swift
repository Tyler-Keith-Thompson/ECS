// Filters written as types, command buffers queued on a world, and the split of a world into
// the part a writer owns. Each test is self-contained.

import WorldModule
import ECSTestSupport
import PropertyBased
import Testing

@Suite("World: filter types")
struct FilterTermTests {
    @Test("Each filter type stands for the filter value of the same name")
    func filterTypes() {
        let with: QueryFilter = .with(Velocity.self)
        let without: QueryFilter = .without(Frozen.self)
        let added: QueryFilter = .added(Health.self)
        let changed: QueryFilter = .changed(Health.self)
        #expect(With<Velocity>.filter == with)
        #expect(Without<Frozen>.filter == without)
        #expect(Added<Health>.filter == added)
        #expect(Changed<Health>.filter == changed)
    }

    @Test("AnyOf of filter types is the anyOf of their filters")
    func anyOfFilterTypes() {
        let expected: QueryFilter = .anyOf(.with(Velocity.self), .without(Frozen.self))
        #expect(AnyOf<With<Velocity>, Without<Frozen>>.filter == expected)
    }

    @Test("A Where's filter applies every filter type")
    func whereFilter() {
        let expected: QueryFilter = QueryFilter().with(Velocity.self).without(Frozen.self)
        #expect(Query<Position>.Where<With<Velocity>, Without<Frozen>>.filter == expected)
    }

    @Test("A Where with no filter types passes everything")
    func emptyWhere() {
        let expected: QueryFilter = QueryFilter()
        #expect(Query<Position>.Where< >.filter == expected)
    }

    @Test("Filter types read the component types they name")
    func filterReads() {
        let access = AnyOf<With<Velocity>, Changed<Health>>._reading(Access())
        #expect(access.conflicts(with: .writes(Velocity.self)))
        #expect(access.conflicts(with: .writes(Health.self)))
        #expect(!access.conflicts(with: .writes(Position.self)))
        #expect(!access.conflicts(with: .reads(Velocity.self, Health.self)))
    }

    @Test("A query filtered by AnyOf of filter types matches a model", .tags(.randomized))
    func anyOfMatchesModel() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            var expected: [Entity] = []
            for _ in 0 ..< Int.random(in: 0 ... 30, using: &generator) {
                let entity = world.spawn(Position(x: 0, y: 0))
                let moving = Bool.random(using: &generator)
                let frozen = Bool.random(using: &generator)
                if moving { world.insert(Velocity(dx: 1, dy: 1), into: entity) }
                if frozen { world.insert(Frozen(), into: entity) }
                if moving || !frozen { expected.append(entity) }
            }
            let query = Query(Position.self).filtered(by: AnyOf<With<Velocity>, Without<Frozen>>.filter)
            let found: [Entity] = world.query(query).map { entity, _ in entity }.sorted()
            #expect(found == expected.sorted())
        }
    }
}

@Suite("World: queued commands")
struct QueuedCommandsTests {
    @Test("Queued buffers apply in the order queued and empty the queue")
    func applyInOrder() {
        var world = World()
        var first = Commands()
        first.spawn(Name("first"))
        var second = Commands()
        second.spawn(Name("second"))
        world.queue(first)
        world.queue(second)
        #expect(world.hasQueuedCommands)
        let spawned = world.applyQueuedCommands()
        let names: [Name] = spawned.map { world[Name.self, of: $0] }
        let expected: [Name] = [Name("first"), Name("second")]
        #expect(names == expected)
        #expect(!world.hasQueuedCommands)
    }

    @Test("Applying with nothing queued changes nothing")
    func applyEmpty() {
        var world = World()
        world.spawn(Name("only"))
        #expect(!world.hasQueuedCommands)
        let spawned = world.applyQueuedCommands()
        #expect(spawned.isEmpty)
        let count: Int = 1
        #expect(world.query(Name.self).count == count)
    }

    @Test("A queued buffer is part of the world's value: a copy keeps its own queue")
    func queueIsValue() {
        var world = World()
        var commands = Commands()
        commands.spawn(Name("queued"))
        let before = world
        world.queue(commands)
        #expect(!before.hasQueuedCommands)
        #expect(world.hasQueuedCommands)
    }
}

@Suite("World: access merging and splitting")
struct WorldSplitTests {
    @Test("A merged access reads and writes what either does")
    func accessMerging() {
        let merged = Access.reads(Velocity.self).merging(.writes(Position.self).writes(resources: Clock.self))
        #expect(merged.conflicts(with: .writes(Velocity.self)))
        #expect(merged.conflicts(with: .reads(Position.self)))
        #expect(merged.conflicts(with: .reads(resources: Clock.self)))
        #expect(!merged.conflicts(with: .reads(Velocity.self)))
        #expect(!Access().merging(Access()).conflicts(with: .writes(Position.self)))
    }

    @Test("A split world gives up what it writes until the part is merged back")
    func splitAndMerge() {
        var world = World()
        world.resources.insert(Clock(ticks: 1))
        let entity = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let access = Access.writes(Position.self).writes(resources: Clock.self)
        var part = world.split(writing: access)
        let empty: Int = 0
        #expect(world.query(Position.self).count == empty)
        #expect(!world.resources.contains(Clock.self))
        let velocities: Int = 1
        #expect(world.query(Velocity.self).count == velocities)
        part.update(Position.self) { position, _ in position.x = 9 }
        part.resources[Clock.self].ticks = 2
        world.merge(writing: access, from: part)
        let moved: Position = Position(x: 9, y: 0)
        let clock: Clock = Clock(ticks: 2)
        #expect(world[Position.self, of: entity] == moved)
        #expect(world.resources[Clock.self] == clock)
    }

    @Test("Splitting leaves another copy of the world unchanged")
    func splitKeepsCopies() {
        var world = World()
        let entity = world.spawn(Position(x: 0, y: 0))
        let copy = world
        let access = Access.writes(Position.self)
        var part = world.split(writing: access)
        part.update(Position.self) { position, _ in position.x = 5 }
        world.merge(writing: access, from: part)
        let original: Position = Position(x: 0, y: 0)
        let moved: Position = Position(x: 5, y: 0)
        #expect(copy[Position.self, of: entity] == original)
        #expect(world[Position.self, of: entity] == moved)
    }

    @Test("Commands queued on a part are queued on the world it merges into")
    func partQueue() {
        var world = World()
        let access = Access.writes(Position.self)
        var part = world.split(writing: access)
        var commands = Commands()
        commands.spawn(Name("from part"))
        part.queue(commands)
        world.merge(writing: access, from: part)
        #expect(world.hasQueuedCommands)
    }
}
