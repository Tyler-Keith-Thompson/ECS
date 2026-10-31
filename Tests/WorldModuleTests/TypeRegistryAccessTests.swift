// Reading and inserting components and resources by their registered names. Self-contained.

import ECSTestSupport
import Foundation
import PropertyBased
import Testing
import WorldModule

private struct Vault: Resource, Codable, Hashable {
    var gold: Int
}

/// A component requiring a Health, to check that inserting by name adds required components.
private struct Plated: Component, Codable, Hashable {
    var plates: Int
    static var required: some WorldModule.Bundle { Health(5) }
}

/// What the insert hook saw.
private struct RegistryHookLog: Resource {
    var entries: [String] = []
}

/// A world decoded from data naming one component, through the registry in `userInfo`.
private struct DecodedShip: Decodable {
    var world = World()
    let ship: Entity

    init(from decoder: any Decoder) throws {
        let registry = decoder.userInfo[.typeRegistry] as! TypeRegistry
        ship = world.spawn()
        try registry.insert(componentNamed: "Position", into: ship, in: &world) { type in
            try type.init(from: decoder)
        }
    }
}

@Suite("Type registry: access by name")
struct TypeRegistryAccessTests {
    @Test("Reading a component by name gives the component the entity holds, encodable with any encoder")
    func readComponent() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        try registry.register(Health.self, named: "Health")
        var world = World()
        let ship = world.spawn(Position(x: 3, y: 4), Health(9))
        let position = registry.component(named: "Position", of: ship, in: world)
        let health = try registry.component(checkedNamed: "Health", of: ship, in: world)
        let expectedPosition = Position(x: 3, y: 4)
        let expectedHealth = Health(9)
        #expect(position as? Position == expectedPosition)
        #expect(health as? Health == expectedHealth)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(position) == encoder.encode(expectedPosition))
    }

    @Test("The checked read throws unregisteredName, staleEntity or missingValue")
    func checkedReadErrors() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        try registry.register(Health.self, named: "Health")
        try registry.register(resource: Vault.self, named: "Vault")
        var world = World()
        let ship = world.spawn(Position(x: 0, y: 0))
        let gone = world.spawn(Position(x: 1, y: 1))
        world.despawn(gone)
        #expect(throws: TypeRegistryLookupError.unregisteredName) { try registry.component(checkedNamed: "Velocity", of: ship, in: world) }
        #expect(throws: TypeRegistryLookupError.unregisteredName) { try registry.component(checkedNamed: "Vault", of: ship, in: world) }
        #expect(throws: TypeRegistryLookupError.staleEntity) { try registry.component(checkedNamed: "Position", of: gone, in: world) }
        #expect(throws: TypeRegistryLookupError.missingValue) { try registry.component(checkedNamed: "Health", of: ship, in: world) }
    }

    @Test("Reading a component by an unregistered name traps")
    func readUnregisteredTraps() async {
        await #expect(processExitsWith: .failure) {
            let registry = TypeRegistry()
            var world = World()
            let ship = world.spawn(Position(x: 0, y: 0))
            _ = registry.component(named: "Position", of: ship, in: world)
        }
    }

    @Test("Reading a component by name of a stale entity traps")
    func readStaleTraps() async {
        await #expect(processExitsWith: .failure) {
            var registry = TypeRegistry()
            try registry.register(Position.self, named: "Position")
            var world = World()
            let gone = world.spawn(Position(x: 0, y: 0))
            world.despawn(gone)
            _ = registry.component(named: "Position", of: gone, in: world)
        }
    }

    @Test("Reading a component by name that the entity doesn't hold traps")
    func readMissingTraps() async {
        await #expect(processExitsWith: .failure) {
            var registry = TypeRegistry()
            try registry.register(Health.self, named: "Health")
            var world = World()
            let ship = world.spawn(Position(x: 0, y: 0))
            _ = registry.component(named: "Health", of: ship, in: world)
        }
    }

    @Test("Inserting a component by name decodes the registered type, replaces a held one, runs insert hooks and adds required components")
    func insertComponent() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        try registry.register(Plated.self, named: "Plated")
        var world = World()
        world.resources.insert(RegistryHookLog())
        world.onInsert(Position.self) { world, entity in
            world.resources[RegistryHookLog.self].entries.append("insert \(world[Position.self, of: entity].x)")
        }
        let ship = world.spawn(Position(x: 1, y: 1))
        let positionData = Data(#"{"x": 5, "y": 6}"#.utf8)
        let armoredData = Data(#"{"plates": 3}"#.utf8)
        var askedFor: [String] = []
        try registry.insert(componentNamed: "Position", into: ship, in: &world) { type in
            askedFor.append(String(describing: type))
            return try JSONDecoder().decode(type, from: positionData)
        }
        try registry.insert(componentNamed: "Plated", checkedInto: ship, in: &world) { type in
            try JSONDecoder().decode(type, from: armoredData)
        }
        let expectedAsked = ["Position"]
        let expectedPosition = Position(x: 5, y: 6)
        let expectedPlated = Plated(plates: 3)
        let expectedHealth = Health(5)
        let expectedLog = ["insert 1.0", "insert 5.0"]
        #expect(askedFor == expectedAsked)
        #expect(world[Position.self, of: ship] == expectedPosition)
        #expect(world[Plated.self, of: ship] == expectedPlated)
        #expect(world[Health.self, of: ship] == expectedHealth)
        #expect(world.resources[RegistryHookLog.self].entries == expectedLog)
    }

    @Test("Inserting by name from inside init(from:) decodes with the caller's Decoder")
    func insertFromDecoder() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        let decoder = JSONDecoder()
        decoder.userInfo[.typeRegistry] = registry
        let decoded = try decoder.decode(DecodedShip.self, from: Data(#"{"x": 7, "y": 8}"#.utf8))
        let expected = Position(x: 7, y: 8)
        #expect(decoded.world[Position.self, of: decoded.ship] == expected)
    }

    @Test("A decoding error from the closure propagates and leaves the world unchanged")
    func insertDecodingError() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        var world = World()
        let ship = world.spawn(Position(x: 1, y: 2))
        let before = world
        let malformed = Data(#"{"x": "five"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try registry.insert(componentNamed: "Position", into: ship, in: &world) { type in
                try JSONDecoder().decode(type, from: malformed)
            }
        }
        #expect(throws: DecodingError.self) {
            try registry.insert(componentNamed: "Position", checkedInto: ship, in: &world) { type in
                try JSONDecoder().decode(type, from: malformed)
            }
        }
        let expected = Position(x: 1, y: 2)
        #expect(world[Position.self, of: ship] == expected)
        #expect(world.changeTick == before.changeTick)
    }

    @Test("The checked insert throws unregisteredName or staleEntity without calling the closure")
    func checkedInsertErrors() throws {
        var registry = TypeRegistry()
        try registry.register(Position.self, named: "Position")
        var world = World()
        let ship = world.spawn()
        let gone = world.spawn()
        world.despawn(gone)
        var calls = 0
        #expect(throws: TypeRegistryLookupError.unregisteredName) {
            try registry.insert(componentNamed: "Velocity", checkedInto: ship, in: &world) { type in
                calls += 1
                return try JSONDecoder().decode(type, from: Data())
            }
        }
        #expect(throws: TypeRegistryLookupError.staleEntity) {
            try registry.insert(componentNamed: "Position", checkedInto: gone, in: &world) { type in
                calls += 1
                return try JSONDecoder().decode(type, from: Data())
            }
        }
        let none = 0
        #expect(calls == none)
        #expect(!world.contains(Position.self, in: ship))
    }

    @Test("Inserting a component by an unregistered name traps")
    func insertUnregisteredTraps() async {
        await #expect(processExitsWith: .failure) {
            let registry = TypeRegistry()
            var world = World()
            let ship = world.spawn()
            registry.insert(componentNamed: "Position", into: ship, in: &world) { _ in Position(x: 0, y: 0) }
        }
    }

    @Test("Inserting a component by name into a stale entity traps")
    func insertStaleTraps() async {
        await #expect(processExitsWith: .failure) {
            var registry = TypeRegistry()
            try registry.register(Position.self, named: "Position")
            var world = World()
            let gone = world.spawn()
            world.despawn(gone)
            registry.insert(componentNamed: "Position", into: gone, in: &world) { _ in Position(x: 0, y: 0) }
        }
    }

    @Test("A decode closure returning a value of another type traps")
    func wrongTypeTraps() async {
        await #expect(processExitsWith: .failure) {
            var registry = TypeRegistry()
            try registry.register(Position.self, named: "Position")
            var world = World()
            let ship = world.spawn()
            registry.insert(componentNamed: "Position", into: ship, in: &world) { _ in Health(1) }
        }
    }

    @Test("Reading and inserting a resource by name, with the checked errors")
    func resources() throws {
        var registry = TypeRegistry()
        try registry.register(resource: Vault.self, named: "Vault")
        try registry.register(Position.self, named: "Position")
        var world = World()
        #expect(throws: TypeRegistryLookupError.missingValue) { try registry.resource(checkedNamed: "Vault", in: world.resources) }
        #expect(throws: TypeRegistryLookupError.unregisteredName) { try registry.resource(checkedNamed: "Position", in: world.resources) }
        let data = Data(#"{"gold": 15}"#.utf8)
        try registry.insert(resourceNamed: "Vault", into: &world.resources) { type in
            try JSONDecoder().decode(type, from: data)
        }
        let fifteen = Vault(gold: 15)
        #expect(registry.resource(named: "Vault", in: world.resources) as? Vault == fifteen)
        #expect(try registry.resource(checkedNamed: "Vault", in: world.resources) as? Vault == fifteen)
        let replacement = Data(#"{"gold": 20}"#.utf8)
        try registry.insert(resourceNamed: "Vault", checkedInto: &world.resources) { type in
            try JSONDecoder().decode(type, from: replacement)
        }
        let twenty = Vault(gold: 20)
        #expect(world.resources[Vault.self] == twenty)
        #expect(throws: TypeRegistryLookupError.unregisteredName) {
            try registry.insert(resourceNamed: "Position", checkedInto: &world.resources) { type in
                try JSONDecoder().decode(type, from: replacement)
            }
        }
    }

    @Test("Reading a resource by an unregistered name traps")
    func resourceUnregisteredTraps() async {
        await #expect(processExitsWith: .failure) {
            let registry = TypeRegistry()
            var world = World()
            world.resources.insert(Vault(gold: 1))
            _ = registry.resource(named: "Vault", in: world.resources)
        }
    }

    @Test("Reading a resource by name that the world doesn't hold traps")
    func resourceMissingTraps() async {
        await #expect(processExitsWith: .failure) {
            var registry = TypeRegistry()
            try registry.register(resource: Vault.self, named: "Vault")
            let world = World()
            _ = registry.resource(named: "Vault", in: world.resources)
        }
    }

    @Test("Inserting a resource by an unregistered name traps")
    func insertResourceUnregisteredTraps() async {
        await #expect(processExitsWith: .failure) {
            let registry = TypeRegistry()
            var world = World()
            registry.insert(resourceNamed: "Vault", into: &world.resources) { _ in Vault(gold: 1) }
        }
    }

    @Test("Copying components by name through JSON reproduces them in another world", .tags(.randomized))
    func copyByName() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var registry = TypeRegistry()
            try! registry.register(Position.self, named: "Position")
            try! registry.register(Health.self, named: "Health")
            var source = World()
            var target = World()
            var pairs: [(Entity, Entity)] = []
            for _ in 0 ..< Int.random(in: 0 ... 20, using: &generator) {
                let entity = source.spawn()
                if Bool.random(using: &generator) {
                    source.insert(Position(x: Double(Int.random(in: -9 ... 9, using: &generator)), y: 1), into: entity)
                }
                if Bool.random(using: &generator) {
                    source.insert(Health(Int.random(in: 0 ... 9, using: &generator)), into: entity)
                }
                pairs.append((entity, target.spawn()))
            }
            for (from, to) in pairs {
                for name in registry.componentNames {
                    guard let component = try? registry.component(checkedNamed: name, of: from, in: source) else { continue }
                    let data = try! JSONEncoder().encode(component)
                    try! registry.insert(componentNamed: name, into: to, in: &target) { type in
                        try JSONDecoder().decode(type, from: data)
                    }
                }
            }
            for (from, to) in pairs {
                let sourcePosition: Position? = source[Position?.self, of: from]
                let targetPosition: Position? = target[Position?.self, of: to]
                let sourceHealth: Health? = source[Health?.self, of: from]
                let targetHealth: Health? = target[Health?.self, of: to]
                #expect(sourcePosition == targetPosition)
                #expect(sourceHealth == targetHealth)
            }
        }
    }
}
