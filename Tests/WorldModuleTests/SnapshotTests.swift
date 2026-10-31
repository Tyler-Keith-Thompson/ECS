// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import Foundation
import PropertyBased
import Testing
import WorldModule

@Suite("Snapshots")
struct SnapshotTests {
    @Test("A world restored from a JSON snapshot has the same entities, components and hierarchy")
    func roundTrip() throws {
        var world = World()
        let ship = world.spawn(Position(x: 1, y: 2), Health(3))
        let turret = world.spawn(Position(x: 4, y: 5))
        let gone = world.spawn(Health(9))
        world.despawn(gone)
        try world.addChild(turret, to: ship)
        let data = try JSONEncoder().encode(world.snapshot(Position.self, Health.self))
        let snapshot = try JSONDecoder().decode(WorldSnapshot<Position, Health>.self, from: data)
        let restored = World(restoring: snapshot)
        let expectedEntities = [ship, turret]
        #expect(Array(restored.entities) == expectedEntities)
        #expect(restored[Position.self, of: ship] == Position(x: 1, y: 2))
        #expect(restored[Health.self, of: ship] == Health(3))
        #expect(restored[Position.self, of: turret] == Position(x: 4, y: 5))
        #expect(!restored.contains(gone))
        #expect(restored.parent(of: turret) == ship)
    }

    @Test("The restored world hands out the same handles from later spawns")
    func laterSpawns() throws {
        var world = World()
        let entities = (0 ..< 5).map { _ in world.spawn() }
        world.despawn(entities[1])
        world.despawn(entities[3])
        var restored = World(restoring: world.snapshot())
        let fromOriginal = [world.spawn(), world.spawn(), world.spawn()]
        let fromRestored = [restored.spawn(), restored.spawn(), restored.spawn()]
        #expect(fromRestored == fromOriginal)
    }

    @Test("Component types left out of the snapshot are left out of the restored world")
    func leftOut() throws {
        var world = World()
        let entity = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1))
        let restored = World(restoring: world.snapshot(Position.self))
        #expect(restored.contains(Position.self, in: entity))
        #expect(!restored.contains(Velocity.self, in: entity))
    }

    @Test("Queries over a restored world list entities in the original order")
    func queryOrder() throws {
        var world = World()
        let entities = (0 ..< 6).map { world.spawn(Health($0)) }
        world.remove(Health.self, from: entities[1])
        let restored = World(restoring: world.snapshot(Health.self))
        let original = world.query(Health.self).map(\.entity)
        let fromRestored = restored.query(Health.self).map(\.entity)
        #expect(fromRestored == original)
    }

    @Test("An empty world round-trips")
    func empty() throws {
        let world = World()
        let data = try JSONEncoder().encode(world.snapshot(Health.self))
        let snapshot = try JSONDecoder().decode(WorldSnapshot<Health>.self, from: data)
        let restored = World(restoring: snapshot)
        #expect(restored.isEmpty)
        #expect(snapshot.count == 0)
    }

    @Test("Decoding data no world could produce throws dataCorrupted")
    func corrupted() throws {
        let staleComponent = #"{"generations":[0],"vacant":[0],"families":[],"components":[{"entities":[{"index":0,"generation":0}],"values":[{"current":1}]}]}"#
        let repeatedVacancy = #"{"generations":[0],"vacant":[0,0],"families":[],"components":[{"entities":[],"values":[]}]}"#
        let mismatchedRows = #"{"generations":[0],"vacant":[],"families":[],"components":[{"entities":[{"index":0,"generation":0}],"values":[]}]}"#
        let cycle = #"{"generations":[0,0],"vacant":[],"families":[{"parent":{"index":0,"generation":0},"children":[{"index":1,"generation":0}]},{"parent":{"index":1,"generation":0},"children":[{"index":0,"generation":0}]}],"components":[{"entities":[],"values":[]}]}"#
        let twoParents = #"{"generations":[0,0,0],"vacant":[],"families":[{"parent":{"index":0,"generation":0},"children":[{"index":2,"generation":0}]},{"parent":{"index":1,"generation":0},"children":[{"index":2,"generation":0}]}],"components":[{"entities":[],"values":[]}]}"#
        for json in [staleComponent, repeatedVacancy, mismatchedRows, cycle, twoParents] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(WorldSnapshot<Health>.self, from: Data(json.utf8))
            }
        }
        let valid = #"{"generations":[0,0],"vacant":[],"families":[{"parent":{"index":0,"generation":0},"children":[{"index":1,"generation":0}]}],"components":[{"entities":[{"index":1,"generation":0}],"values":[{"current":1}]}]}"#
        let snapshot = try JSONDecoder().decode(WorldSnapshot<Health>.self, from: Data(valid.utf8))
        let world = World(restoring: snapshot)
        #expect(world[Health.self, of: Entity(index: 1, generation: 0)] == Health(1))
        #expect(world.parent(of: Entity(index: 1, generation: 0)) == Entity(index: 0, generation: 0))
    }

    @Test("Any world built from random operations round-trips through JSON", .tags(.randomized))
    func randomRoundTrip() async {
        let operations = Gen.int(in: 0 ... 1_000_000).array(of: 0 ... 200)
        await propertyCheck(count: 100, input: operations) { operations in
            var world = World()
            var live: [Entity] = []
            for code in operations {
                let argument = code / 5
                let target = live.isEmpty ? nil : live[argument % live.count]
                switch (code % 5, target) {
                case (0, _), (_, nil):
                    live.append(world.spawn(Health(argument), Name("\(argument)")))
                case let (1, entity?):
                    world.insert(Position(x: Double(argument), y: 0), into: entity)
                case let (2, entity?):
                    world.remove(Name.self, from: entity)
                case let (3, entity?):
                    try? world.addChild(live[(argument / 3) % live.count], to: entity)
                default:
                    world.despawn(target!)
                    live.removeAll { !world.contains($0) }
                }
            }
            let data = try! JSONEncoder().encode(world.snapshot(Health.self, Name.self, Position.self))
            let snapshot = try! JSONDecoder().decode(WorldSnapshot<Health, Name, Position>.self, from: data)
            var restored = World(restoring: snapshot)
            #expect(Array(restored.entities) == Array(world.entities))
            for entity in world.entities {
                #expect((try? restored[checked: Health.self, of: entity]) == (try? world[checked: Health.self, of: entity]))
                #expect((try? restored[checked: Name.self, of: entity]) == (try? world[checked: Name.self, of: entity]))
                #expect((try? restored[checked: Position.self, of: entity]) == (try? world[checked: Position.self, of: entity]))
                #expect(restored.parent(of: entity) == world.parent(of: entity))
                #expect(restored.children(of: entity) == world.children(of: entity))
            }
            #expect(restored.spawn() == world.spawn())
        }
    }
}
