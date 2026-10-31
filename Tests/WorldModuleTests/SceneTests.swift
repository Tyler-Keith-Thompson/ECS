// Scenes saved through a type registry. Self-contained.

import ECSTestSupport
import Foundation
import PropertyBased
import Testing
import WorldModule

struct Score: Resource, Hashable, Codable {
    var points: Int
}

struct Admires: Relation, Hashable, Codable {}

@Suite("Scenes and the type registry")
struct SceneTests {
    @Test("A world restored from a JSON scene has the same entities, components, hierarchy and resources")
    func roundTrip() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        try registry.register(Health.self, named: "Health")
        try registry.register(resource: Score.self, named: "Score")
        var world = World()
        let ship = world.spawn(Position(x: 1, y: 2), Health(3))
        let gone = world.spawn()
        let turret = world.spawn(Position(x: 4, y: 5), Name("turret"))
        world.despawn(gone)
        try world.addChild(turret, to: ship)
        world.resources.insert(Score(points: 7))
        let data = try JSONEncoder().encode(world.scene(registry))
        let decoder = JSONDecoder()
        decoder.userInfo[.typeRegistry] = registry
        let restored = World(restoring: try decoder.decode(Scene.self, from: data))
        let expectedEntities = [ship, turret]
        #expect(Array(restored.entities) == expectedEntities)
        #expect(restored[Position.self, of: ship] == Position(x: 1, y: 2))
        #expect(restored[Health.self, of: ship] == Health(3))
        #expect(restored[Position.self, of: turret] == Position(x: 4, y: 5))
        #expect(!restored.contains(Name.self, in: turret))
        #expect(!restored.contains(gone))
        #expect(restored.parent(of: turret) == ship)
        #expect(restored.resources[Score.self] == Score(points: 7))
        #expect(restored.snapshot(Position.self, Health.self) == world.snapshot(Position.self, Health.self))
    }

    @Test("Relations are saved by registering their Targets component")
    func relations() throws {
        var registry = TypeRegistry()
        try registry.register(Targets<Admires>.self, named: "Admires")
        var world = World()
        let alice = world.spawn()
        let bob = world.spawn()
        world.relate(alice, Admires(), to: bob)
        let decoder = JSONDecoder()
        decoder.userInfo[.typeRegistry] = registry
        let data = try JSONEncoder().encode(world.scene(registry))
        let restored = World(restoring: try decoder.decode(Scene.self, from: data))
        let expectedTargets: [Entity] = [bob]
        let expectedSources: [Entity] = [alice]
        #expect(Array(restored.targets(Admires.self, of: alice)) == expectedTargets)
        #expect(Array(restored.sources(Admires.self, of: bob)) == expectedSources)
    }

    @Test("A scene names the registered types in registration order, and counts live entities")
    func names() throws {
        var registry = TypeRegistry()
        try registry.register(Health.self, named: "Health")
        try registry.register(Position.self)
        try registry.register(resource: Score.self, named: "Score")
        let expectedComponents: [String] = ["Health", String(reflecting: Position.self)]
        #expect(registry.componentNames == expectedComponents)
        var world = World()
        world.spawn(Health(1))
        let gone = world.spawn()
        world.despawn(gone)
        let scene = world.scene(registry)
        #expect(scene.componentNames == expectedComponents)
        let noResources: [String] = []
        #expect(scene.resourceNames == noResources)
        let expectedCount = 1
        #expect(scene.count == expectedCount)
    }

    @Test("Registering a type again under its name changes nothing")
    func registeringAgain() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        try registry.register(Position.self, named: "Position")
        let expected: [String] = ["Position"]
        #expect(registry.componentNames == expected)
    }

    @Test("Registration throws for a taken name or a type with another name, leaving the registry unchanged")
    func registrationErrors() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        try registry.register(resource: Score.self, named: "Score")
        #expect(throws: TypeRegistryError.nameTaken) {
            try registry.register(Velocity.self, named: "Position")
        }
        #expect(throws: TypeRegistryError.typeAlreadyRegistered) {
            try registry.register(Position.self, named: "Place")
        }
        #expect(throws: TypeRegistryError.typeAlreadyRegistered) {
            try registry.register(resource: Score.self, named: "Points")
        }
        try registry.register(resource: Gold.self, named: "Position")
        let expectedComponents: [String] = ["Position"]
        let expectedResources: [String] = ["Score", "Position"]
        #expect(registry.componentNames == expectedComponents)
        #expect(registry.resourceNames == expectedResources)
    }

    @Test("Decoding without a registry, or with one missing a saved type, throws dataCorrupted")
    func decodingErrors() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        try registry.register(resource: Score.self, named: "Score")
        var world = World()
        world.spawn(Position(x: 0, y: 0))
        world.resources.insert(Score(points: 1))
        let data = try JSONEncoder().encode(world.scene(registry))
        func decode(with registry: TypeRegistry?) throws -> Scene {
            let decoder = JSONDecoder()
            if let registry { decoder.userInfo[.typeRegistry] = registry }
            return try decoder.decode(Scene.self, from: data)
        }
        func isCorrupted(_ error: any Error) -> Bool {
            if case .dataCorrupted = error as? DecodingError { return true }
            return false
        }
        #expect(performing: { try decode(with: nil) }, throws: isCorrupted)
        var componentsOnly = TypeRegistry()
        try componentsOnly.register(Position.self, named: "Position")
        #expect(performing: { try decode(with: componentsOnly) }, throws: isCorrupted)
        var resourcesOnly = TypeRegistry()
        try resourcesOnly.register(resource: Score.self, named: "Score")
        #expect(performing: { try decode(with: resourcesOnly) }, throws: isCorrupted)
    }

    @Test("A registered type the data does not name is left out")
    func typesNotSaved() throws {
        var saving = TypeRegistry()
        try saving.register(Position.self, named: "Position")
        var loading = saving
        try loading.register(Health.self, named: "Health")
        try loading.register(resource: Score.self, named: "Score")
        var world = World()
        let ship = world.spawn(Position(x: 1, y: 1), Health(2))
        let data = try JSONEncoder().encode(world.scene(saving))
        let decoder = JSONDecoder()
        decoder.userInfo[.typeRegistry] = loading
        let scene = try decoder.decode(Scene.self, from: data)
        let expected: [String] = ["Position"]
        #expect(scene.componentNames == expected)
        let restored = World(restoring: scene)
        #expect(restored[Position.self, of: ship] == Position(x: 1, y: 1))
        #expect(!restored.contains(Health.self, in: ship))
        #expect(!restored.resources.contains(Score.self))
    }

    @Test("Decoding rejects data no world could have produced")
    func corruptData() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        let decoder = JSONDecoder()
        decoder.userInfo[.typeRegistry] = registry
        let deadEntity = #"{"generations":[1],"vacant":[0],"families":[],"components":{"Position":{"entities":[{"index":0,"generation":1}],"values":[{"x":0,"y":0}]}},"resources":{}}"#
        let cycle = #"{"generations":[0,0],"vacant":[],"families":[{"parent":{"index":0,"generation":0},"children":[{"index":1,"generation":0}]},{"parent":{"index":1,"generation":0},"children":[{"index":0,"generation":0}]}],"components":{},"resources":{}}"#
        func isCorrupted(_ error: any Error) -> Bool {
            if case .dataCorrupted = error as? DecodingError { return true }
            return false
        }
        for json in [deadEntity, cycle] {
            let data = Data(json.utf8)
            #expect(performing: { try decoder.decode(Scene.self, from: data) }, throws: isCorrupted)
        }
    }

    @Test("An empty world round-trips")
    func emptyWorld() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        let decoder = JSONDecoder()
        decoder.userInfo[.typeRegistry] = registry
        let data = try JSONEncoder().encode(World().scene(registry))
        let restored = World(restoring: try decoder.decode(Scene.self, from: data))
        #expect(restored.isEmpty)
    }

    @Test("A scene round-trip equals a snapshot of the same types under random changes", .tags(.randomized))
    func matchesSnapshot() async throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        try registry.register(Health.self, named: "Health")
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 50, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            var alive: [Entity] = []
            for _ in 0 ..< Int.random(in: 0 ... 40, using: &generator) {
                let choice = Int.random(in: 0 ..< 5, using: &generator)
                if choice == 0 || alive.isEmpty {
                    alive.append(world.spawn(Position(x: Double(alive.count), y: 0)))
                    continue
                }
                let entity = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                switch choice {
                case 1: world.insert(Health(Int.random(in: 0 ..< 9, using: &generator)), into: entity)
                case 2: _ = world.remove(Position.self, from: entity)
                case 3:
                    let parent = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                    _ = try? world.addChild(entity, to: parent)
                default:
                    world.despawn(entity)
                    alive = alive.filter { world.contains($0) }
                }
            }
            let decoder = JSONDecoder()
            decoder.userInfo[.typeRegistry] = registry
            let data = try JSONEncoder().encode(world.scene(registry))
            let restored = World(restoring: try decoder.decode(Scene.self, from: data))
            #expect(restored.snapshot(Position.self, Health.self) == world.snapshot(Position.self, Health.self))
        }
    }
}

struct Gold: Resource, Codable {
    var coins: Int
}

/// The entity a turret aims at, remapped when its scene is spawned.
struct Aim: Component, Codable, MapEntities {
    var target: Entity

    mutating func mapEntities(_ map: (Entity) -> Entity) {
        target = map(target)
    }
}

/// Whom an entity follows; not remapped.
struct Follows: Component, Codable {
    var leader: Entity
}

@Suite("Spawning scenes")
struct SceneSpawnTests {
    @Test("Spawning a scene adds new entities with its components, hierarchy, relations and resources")
    func spawn() throws {
        var registry = TypeRegistry()
        try registry.register(Name.self, named: "Name")
        try registry.register(Targets<Admires>.self, named: "Admires")
        try registry.register(resource: Score.self, named: "Score")
        var prefab = World()
        let ship = prefab.spawn(Name("ship"))
        let gone = prefab.spawn()
        let deck = prefab.spawn(Name("deck"))
        prefab.despawn(gone)
        try prefab.addChild(deck, to: ship)
        prefab.relate(deck, Admires(), to: ship)
        prefab.resources.insert(Score(points: 4))
        let decoder = JSONDecoder()
        decoder.userInfo[.typeRegistry] = registry
        let scene = try decoder.decode(Scene.self, from: try JSONEncoder().encode(prefab.scene(registry)))
        var world = World()
        let existing = world.spawn(Name("existing"))
        let first = world.spawn(contentsOf: scene)
        let second = world.spawn(contentsOf: scene)
        let expectedCount = 5
        #expect(world.count == expectedCount)
        let expectedKeys: Set<Entity> = [ship, deck]
        #expect(Set(first.keys) == expectedKeys)
        for mapping in [first, second] {
            let newShip = try #require(mapping[ship])
            let newDeck = try #require(mapping[deck])
            #expect(world[Name.self, of: newShip] == Name("ship"))
            #expect(world[Name.self, of: newDeck] == Name("deck"))
            #expect(world.parent(of: newDeck) == newShip)
            let expectedTargets: [Entity] = [newShip]
            #expect(Array(world.targets(Admires.self, of: newDeck)) == expectedTargets)
        }
        #expect(Set(first.values).isDisjoint(with: second.values))
        #expect(!first.values.contains(existing))
        #expect(world.resources[Score.self] == Score(points: 4))
    }

    @Test("A component conforming to MapEntities is pointed at the spawned entities; others keep theirs")
    func mapping() throws {
        var registry = TypeRegistry()
        try registry.register(Aim.self, named: "Aim")
        try registry.register(Follows.self, named: "Follows")
        var prefab = World()
        let target = prefab.spawn()
        let turret = prefab.spawn(Aim(target: target), Follows(leader: target))
        let outside = Entity(index: 99, generation: 0)
        let stray = prefab.spawn(Aim(target: outside))
        var world = World()
        let mapping = world.spawn(contentsOf: prefab.scene(registry))
        let newTurret = try #require(mapping[turret])
        let newStray = try #require(mapping[stray])
        #expect(world[Aim.self, of: newTurret].target == mapping[target])
        #expect(world[Follows.self, of: newTurret].leader == target)
        #expect(world[Aim.self, of: newStray].target == outside)
    }

    @Test("Spawning runs hooks and an empty scene spawns nothing")
    func hooksAndEmpty() throws {
        var registry = TypeRegistry()
        try registry.register(Name.self, named: "Name")
        var prefab = World()
        prefab.spawn(Name("a"))
        var world = World()
        world.onAdd(Name.self) { world, _ in world.resources[Score.self].points += 1 }
        world.resources.insert(Score(points: 0))
        world.spawn(contentsOf: prefab.scene(registry))
        let expectedPoints = 1
        #expect(world.resources[Score.self].points == expectedPoints)
        let none = world.spawn(contentsOf: World().scene(registry))
        #expect(none.isEmpty)
    }
}
