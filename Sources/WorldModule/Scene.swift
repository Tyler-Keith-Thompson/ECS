/// A list of the component and resource types that a scene saves, each under a name that
/// identifies it in saved data.
///
/// A registry lets you save whole worlds without listing their types at each call. Register
/// each type once, when your program starts, then take scenes with ``World/scene(_:)``.
/// Decoding a ``Scene`` needs the same registry, which you pass in the decoder's `userInfo`
/// under `CodingUserInfoKey.typeRegistry`:
///
/// ```swift
/// import Foundation
///
/// var registry = TypeRegistry()
/// try registry.register(Position.self, named: "Position")
/// try registry.register(resource: Treasury.self, named: "Treasury")
///
/// var world = World()
/// world.resources.insert(Treasury(gold: 120))
/// let ship = world.spawn(Position(x: 3, y: 4))
/// let data = try JSONEncoder().encode(world.scene(registry))
///
/// let decoder = JSONDecoder()
/// decoder.userInfo[.typeRegistry] = registry
/// let restored = World(restoring: try decoder.decode(Scene.self, from: data))
/// print(restored[Position.self, of: ship])
/// // Prints "Position(x: 3.0, y: 4.0)"
/// print(restored.resources[Treasury.self].gold)
/// // Prints "120"
/// ```
///
/// A scene always saves the hierarchy (``ChildOf``). To save another relation, register its
/// ``Targets`` component, such as `Targets<Likes>`.
@frozen
public struct TypeRegistry: Sendable {
    @usableFromInline var components: [ComponentRegistration] = []
    @usableFromInline var resources: [ResourceRegistration] = []

    /// Creates an empty registry.
    @inlinable
    public init() {}

    /// The names of the registered component types, in the order they were registered.
    @inlinable
    public var componentNames: [String] { components.map(\.name) }

    /// The names of the registered resource types, in the order they were registered.
    @inlinable
    public var resourceNames: [String] { resources.map(\.name) }

    /// Registers a component type under a name, so scenes save its components.
    ///
    /// Registering a type again under the same name changes nothing.
    ///
    /// ```swift
    /// var registry = TypeRegistry()
    /// try registry.register(Position.self, named: "Position")
    /// try registry.register(Health.self, named: "Health")
    /// print(registry.componentNames)
    /// // Prints "["Position", "Health"]"
    /// ```
    ///
    /// - Parameters:
    ///   - type: The component type to register.
    ///   - name: The name that saved data identifies the type by. The default is the type's
    ///     full name, such as `"MyGame.Position"`. Give a name of your own so that saved data
    ///     stays readable after you rename the type or its module.
    /// - Throws: ``TypeRegistryError/nameTaken`` if another component type has `name`, or
    ///   ``TypeRegistryError/typeAlreadyRegistered`` if `type` is registered under another name.
    ///   The registry is unchanged.
    /// - Complexity: O(*t*), where *t* is the number of registered component types.
    @inlinable
    public mutating func register<C: Component & Codable>(_ type: C.Type, named name: String = String(reflecting: C.self)) throws(TypeRegistryError) {
        let key = ObjectIdentifier(C.self)
        if let existing = components.first(where: { $0.type == key }) {
            guard existing.name == name else { throw .typeAlreadyRegistered }
            return
        }
        guard !components.contains(where: { $0.name == name }) else { throw .nameTaken }
        components.append(ComponentRegistration(name: name, type: key, capture: { world in world.rows(of: C.self) }, decode: { container, key in
            try container.decode(ComponentRows<C>.self, forKey: key)
        }))
    }

    /// Registers a resource type under a name, so scenes save it.
    ///
    /// Registering a type again under the same name changes nothing.
    ///
    /// - Parameters:
    ///   - type: The resource type to register.
    ///   - name: The name that saved data identifies the type by. The default is the type's
    ///     full name.
    /// - Throws: ``TypeRegistryError/nameTaken`` if another resource type has `name`, or
    ///   ``TypeRegistryError/typeAlreadyRegistered`` if `type` is registered under another name.
    ///   The registry is unchanged.
    /// - Complexity: O(*t*), where *t* is the number of registered resource types.
    @inlinable
    public mutating func register<R: Resource & Codable>(resource type: R.Type, named name: String = String(reflecting: R.self)) throws(TypeRegistryError) {
        let key = ObjectIdentifier(R.self)
        if let existing = resources.first(where: { $0.type == key }) {
            guard existing.name == name else { throw .typeAlreadyRegistered }
            return
        }
        guard !resources.contains(where: { $0.name == name }) else { throw .nameTaken }
        resources.append(ResourceRegistration(name: name, type: key, capture: { world in
            world.resources.storage[ObjectIdentifier(R.self)].map { SavedResource(value: $0 as! R) }
        }, decode: { container, key in
            try container.decode(SavedResource<R>.self, forKey: key)
        }))
    }
}

/// An error that indicates why a type couldn't be registered in a ``TypeRegistry``.
///
/// The registry is unchanged when registration throws:
///
/// ```swift
/// var registry = TypeRegistry()
/// try registry.register(Position.self, named: "Position")
///
/// do {
///     try registry.register(Health.self, named: "Position")
/// } catch {
///     print(error)
///     // Prints "nameTaken"
/// }
/// ```
@frozen
public enum TypeRegistryError: Error, Hashable, Sendable {
    /// Another type of the same kind, component or resource, is registered under the name.
    case nameTaken
    /// The type is already registered under another name.
    case typeAlreadyRegistered
}

extension CodingUserInfoKey {
    /// The key under which a decoder's `userInfo` holds the type registry to decode a scene
    /// with.
    ///
    /// Set it before decoding a ``Scene``:
    ///
    /// ```swift
    /// import Foundation
    ///
    /// let decoder = JSONDecoder()
    /// decoder.userInfo[.typeRegistry] = TypeRegistry()
    /// ```
    public static let typeRegistry = CodingUserInfoKey(rawValue: "ECS.TypeRegistry")!
}

/// A registered component type: its name and how to save and decode its components.
@usableFromInline
struct ComponentRegistration: Sendable {
    @usableFromInline let name: String
    @usableFromInline let type: ObjectIdentifier
    @usableFromInline let capture: @Sendable (World) -> any SavedComponents
    @usableFromInline let decode: @Sendable (KeyedDecodingContainer<SceneKey>, SceneKey) throws -> any SavedComponents

    @inlinable
    init(name: String, type: ObjectIdentifier, capture: @escaping @Sendable (World) -> any SavedComponents, decode: @escaping @Sendable (KeyedDecodingContainer<SceneKey>, SceneKey) throws -> any SavedComponents) {
        self.name = name
        self.type = type
        self.capture = capture
        self.decode = decode
    }
}

/// A registered resource type: its name and how to save and decode it.
@usableFromInline
struct ResourceRegistration: Sendable {
    @usableFromInline let name: String
    @usableFromInline let type: ObjectIdentifier
    @usableFromInline let capture: @Sendable (World) -> (any SavedResourceValue)?
    @usableFromInline let decode: @Sendable (KeyedDecodingContainer<SceneKey>, SceneKey) throws -> any SavedResourceValue

    @inlinable
    init(name: String, type: ObjectIdentifier, capture: @escaping @Sendable (World) -> (any SavedResourceValue)?, decode: @escaping @Sendable (KeyedDecodingContainer<SceneKey>, SceneKey) throws -> any SavedResourceValue) {
        self.name = name
        self.type = type
        self.capture = capture
        self.decode = decode
    }
}

/// A key naming a registered type in an encoded ``Scene``.
@usableFromInline
struct SceneKey: CodingKey, Sendable {
    @usableFromInline let stringValue: String

    @inlinable
    init(stringValue: String) {
        self.stringValue = stringValue
    }

    @inlinable
    var intValue: Int? { nil }

    @inlinable
    init?(intValue: Int) { nil }
}

/// One component type's saved entities and values, of a type the code holding it does not know.
@usableFromInline
protocol SavedComponents: Encodable, Sendable {
    var entities: [Entity] { get }
    var valueCount: Int { get }
    func restore(into world: inout World)
    func insert(into world: inout World, mapping: [Entity: Entity])
}

extension ComponentRows: SavedComponents {
    @inlinable
    var valueCount: Int { values.count }

    @inlinable
    func restore(into world: inout World) {
        world.restore(self)
    }

    @inlinable
    func insert(into world: inout World, mapping: [Entity: Entity]) {
        for (entity, value) in zip(entities, values) {
            world.insert(mapped(value, by: mapping), into: mapping[entity]!)
        }
    }
}

/// A type whose values name other entities, which can be pointed at different entities.
///
/// Conform a component that stores entity handles to `MapEntities` so that spawning a scene
/// into a world (``World/spawn(contentsOf:)``) keeps it pointing at the right entities. The
/// world spawns new entities in place of the scene's, then calls ``mapEntities(_:)`` with a
/// closure that maps each of the scene's entities to its replacement.
///
/// The following example declares a component that names the leader an entity follows:
///
/// ```swift
/// struct Follows: Component, Codable, MapEntities {
///     var leader: Entity
///
///     mutating func mapEntities(_ map: (Entity) -> Entity) {
///         leader = map(leader)
///     }
/// }
/// ```
///
/// A relation's ``Targets`` component already conforms.
public protocol MapEntities {
    /// Replaces every entity the value names with the entity a closure maps it to.
    ///
    /// - Parameter map: A closure that returns the entity to name in place of the given one.
    mutating func mapEntities(_ map: (Entity) -> Entity)
}

extension Targets: MapEntities {
    /// Replaces each target with the entity a closure maps it to.
    ///
    /// - Parameter map: A closure that returns the entity to name in place of the given one.
    @inlinable
    public mutating func mapEntities(_ map: (Entity) -> Entity) {
        for index in storedEntities.indices {
            storedEntities[index] = map(storedEntities[index])
        }
    }
}

/// `value` with each entity it names replaced by its entry in `mapping`, when it has one.
@inlinable
func mapped<C>(_ value: C, by mapping: [Entity: Entity]) -> C {
    guard var mappable = value as? any MapEntities else { return value }
    mappable.mapEntities { mapping[$0] ?? $0 }
    return mappable as! C
}

/// A saved resource, of a type the code holding it does not know.
@usableFromInline
protocol SavedResourceValue: Encodable, Sendable {
    func insert(into resources: inout Resources)
}

/// A saved resource of type `R`.
@usableFromInline
struct SavedResource<R: Resource & Codable>: SavedResourceValue, Codable {
    @usableFromInline let value: R

    @inlinable
    init(value: R) {
        self.value = value
    }

    @inlinable
    init(from decoder: any Decoder) throws {
        value = try R(from: decoder)
    }

    @inlinable
    func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }

    @inlinable
    func insert(into resources: inout Resources) {
        resources.insert(value)
    }
}

/// A saved copy of a world's entities, hierarchy, and the components and resources of the types
/// a registry names.
///
/// Use a scene to save and load whole worlds, such as a game's save file or a level made in an
/// editor, or to store a group of entities you spawn many times, such as an enemy squad. Take a
/// scene with ``World/scene(_:)``, passing a ``TypeRegistry`` of the types to save. Then either
/// rebuild the whole world with `World(restoring:)`, or add the scene's entities to another
/// world as new ones with ``World/spawn(contentsOf:)``.
///
/// A scene is `Codable`. Encoding needs nothing more; decoding needs the registry in the
/// decoder's `userInfo` under `CodingUserInfoKey.typeRegistry`:
///
/// ```swift
/// import Foundation
///
/// var registry = TypeRegistry()
/// try registry.register(Name.self, named: "Name")
///
/// var world = World()
/// let ship = world.spawn(Name(value: "Ship"))
/// let turret = world.spawn(Name(value: "Turret"))
/// try world.addChild(turret, to: ship)
/// let data = try JSONEncoder().encode(world.scene(registry))
///
/// let decoder = JSONDecoder()
/// decoder.userInfo[.typeRegistry] = registry
/// let scene = try decoder.decode(Scene.self, from: data)
/// print(scene.count)
/// // Prints "2"
///
/// let restored = World(restoring: scene)
/// print(restored.parent(of: turret) == ship)
/// // Prints "true"
/// ```
///
/// Restoring keeps every entity handle, live or stale, meaning the same as in the original
/// world, and the restored world hands out the same handles from later spawns. Types the
/// registry names but the data doesn't are left out.
///
/// A scene holds no hooks, observers, caches, indexes or change ticks, and the restored world's
/// components are all added at its first tick.
///
/// - Note: Decoding throws `DecodingError.dataCorrupted` when the decoder's `userInfo` has no
///   registry, when the data names a type the registry doesn't, or for data that no world could
///   have produced.
public struct Scene: Sendable, Codable {
    @usableFromInline let generations: [UInt32]
    @usableFromInline let vacant: [UInt32]
    @usableFromInline let families: [Family]
    @usableFromInline let components: [(name: String, rows: any SavedComponents)]
    @usableFromInline let resources: [(name: String, value: any SavedResourceValue)]

    @inlinable
    init(generations: [UInt32], vacant: [UInt32], families: [Family], components: [(name: String, rows: any SavedComponents)], resources: [(name: String, value: any SavedResourceValue)]) {
        self.generations = generations
        self.vacant = vacant
        self.families = families
        self.components = components
        self.resources = resources
    }

    /// The number of live entities.
    @inlinable
    public var count: Int { generations.count - vacant.count }

    /// The names of the component types saved, in registration order.
    @inlinable
    public var componentNames: [String] { components.map(\.name) }

    /// The names of the resource types saved, in registration order.
    @inlinable
    public var resourceNames: [String] { resources.map(\.name) }

    enum CodingKeys: String, CodingKey {
        case generations, vacant, families, components, resources
    }

    /// Encodes the scene into the given encoder.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generations, forKey: .generations)
        try container.encode(vacant, forKey: .vacant)
        try container.encode(families, forKey: .families)
        var saved = container.nestedContainer(keyedBy: SceneKey.self, forKey: .components)
        for (name, rows) in components {
            try saved.encode(rows, forKey: SceneKey(stringValue: name))
        }
        var savedResources = container.nestedContainer(keyedBy: SceneKey.self, forKey: .resources)
        for (name, value) in resources {
            try savedResources.encode(value, forKey: SceneKey(stringValue: name))
        }
    }

    /// Creates a scene by decoding from the given decoder, whose `userInfo` holds the type
    /// registry under `CodingUserInfoKey.typeRegistry`.
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: `DecodingError.dataCorrupted` if the decoder has no registry, if the data names
    ///   a type the registry doesn't, or if the data describes a world that no world could have
    ///   produced; or any error the decoder throws.
    public init(from decoder: any Decoder) throws {
        func corrupted(_ description: String) -> DecodingError {
            .dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: description))
        }
        guard let registry = decoder.userInfo[.typeRegistry] as? TypeRegistry else {
            throw corrupted("No TypeRegistry in the decoder's userInfo[.typeRegistry]")
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let generations = try container.decode([UInt32].self, forKey: .generations)
        let vacant = try container.decode([UInt32].self, forKey: .vacant)
        let families = try container.decode([Family].self, forKey: .families)
        let saved = try container.nestedContainer(keyedBy: SceneKey.self, forKey: .components)
        let savedNames = Set(saved.allKeys.map(\.stringValue))
        for name in savedNames.sorted() where !registry.components.contains(where: { $0.name == name }) {
            throw corrupted("Unregistered component type \(name)")
        }
        var components: [(name: String, rows: any SavedComponents)] = []
        for registration in registry.components where savedNames.contains(registration.name) {
            components.append((registration.name, try registration.decode(saved, SceneKey(stringValue: registration.name))))
        }
        let savedResources = try container.nestedContainer(keyedBy: SceneKey.self, forKey: .resources)
        let savedResourceNames = Set(savedResources.allKeys.map(\.stringValue))
        for name in savedResourceNames.sorted() where !registry.resources.contains(where: { $0.name == name }) {
            throw corrupted("Unregistered resource type \(name)")
        }
        var resources: [(name: String, value: any SavedResourceValue)] = []
        for registration in registry.resources where savedResourceNames.contains(registration.name) {
            resources.append((registration.name, try registration.decode(savedResources, SceneKey(stringValue: registration.name))))
        }
        try validateLayout(generations: generations, vacant: vacant, families: families, columns: components.map(\.rows), codingPath: decoder.codingPath)
        self.init(generations: generations, vacant: vacant, families: families, components: components, resources: resources)
    }
}

/// Throws `DecodingError.dataCorrupted` unless the slots, hierarchy and components describe a
/// world some world could have saved.
@usableFromInline
func validateLayout(generations: [UInt32], vacant: [UInt32], families: [Family], columns: [any SavedComponents], codingPath: [any CodingKey]) throws(DecodingError) {
    func corrupted(_ description: String) -> DecodingError {
        .dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: description))
    }
    guard generations.count < Int(UInt32.max) else { throw corrupted("Too many slots") }
    var isLive = [Bool](repeating: true, count: generations.count)
    for slot in vacant {
        guard Int(slot) < generations.count, isLive[Int(slot)] else { throw corrupted("Invalid vacant slot \(slot)") }
        isLive[Int(slot)] = false
    }
    func isLiveEntity(_ entity: Entity) -> Bool {
        Int(entity.index) < generations.count && isLive[Int(entity.index)] && generations[Int(entity.index)] == entity.generation
    }
    for column in columns {
        guard column.entities.count == column.valueCount else { throw corrupted("Mismatched component rows") }
        var seen = Set<Entity>()
        for entity in column.entities {
            guard isLiveEntity(entity), seen.insert(entity).inserted else {
                throw corrupted("Invalid or repeated entity \(entity) in a component column")
            }
        }
    }
    var parentOf: [Entity: Entity] = [:]
    for family in families {
        guard isLiveEntity(family.parent) else { throw corrupted("Invalid parent \(family.parent)") }
        for child in family.children {
            guard isLiveEntity(child), parentOf.updateValue(family.parent, forKey: child) == nil else {
                throw corrupted("Invalid or repeated child \(child)")
            }
        }
    }
    for start in parentOf.keys {
        var steps = 0
        var current = parentOf[start]
        while let walking = current {
            steps += 1
            guard walking != start, steps <= parentOf.count else { throw corrupted("Cyclic hierarchy") }
            current = parentOf[walking]
        }
    }
}

extension World {
    /// Returns a scene of the world's entities, hierarchy, and the components and resources of
    /// the types a registry names.
    ///
    /// Components and resources of other types are left out. See ``Scene`` for an example.
    ///
    /// - Parameter registry: The types to save.
    /// - Returns: A scene of the world.
    /// - Complexity: O(*n*), where *n* is the number of entities and components saved.
    @inlinable
    public func scene(_ registry: TypeRegistry) -> Scene {
        Scene(
            generations: generations,
            vacant: vacant,
            families: families(),
            components: registry.components.map { ($0.name, $0.capture(self)) },
            resources: registry.resources.compactMap { registration in registration.capture(self).map { (registration.name, $0) } }
        )
    }

    /// Each parent with its children, in the order they were added.
    @inlinable
    func families() -> [Family] {
        var families: [Family] = []
        let index = childOfIndex
        for slot in index.sourcesByTarget.indices where !index.sourcesByTarget[slot].isEmpty {
            families.append(Family(parent: Entity(index: UInt32(slot), generation: generations[slot]), children: index.sourcesByTarget[slot]))
        }
        return families
    }

    /// Creates a world from a scene, with the entities, hierarchy, components and resources it
    /// saved.
    ///
    /// Every entity handle means the same in the new world as in the world the scene was taken
    /// of. See ``Scene`` for an example.
    ///
    /// - Parameter scene: The scene to restore.
    /// - Complexity: O(*n*), where *n* is the number of entities and components restored.
    @inlinable
    public init(restoring scene: Scene) {
        self.init(slots: scene.generations, vacant: scene.vacant, families: scene.families)
        for (_, rows) in scene.components {
            rows.restore(into: &self)
        }
        for (_, value) in scene.resources {
            value.insert(into: &resources)
        }
    }

    /// Adds the entities of a scene to the world as new entities, and inserts the scene's
    /// resources.
    ///
    /// Use this method to place a saved group of entities into a world, as many times as you
    /// like: a squad of enemies, a room of a level. Each live entity of the scene is spawned as a
    /// new entity with its components, hierarchy and relations. The scene's resources replace
    /// any of the same types the world holds.
    ///
    /// A component that conforms to ``MapEntities``, such as a relation's ``Targets``, has each
    /// of the scene's entities it names replaced by the entity spawned for it. Entities outside
    /// the scene are left as they are. The following example spawns a squad twice, and each
    /// copy's follower follows its own copy's leader:
    ///
    /// ```swift
    /// var registry = TypeRegistry()
    /// try registry.register(Name.self, named: "Name")
    /// try registry.register(Follows.self, named: "Follows")
    ///
    /// var squad = World()
    /// let leader = squad.spawn(Name(value: "Captain"))
    /// let follower = squad.spawn(Name(value: "Private"), Follows(leader: leader))
    /// let saved = squad.scene(registry)
    ///
    /// var world = World()
    /// let alpha = world.spawn(contentsOf: saved)
    /// let bravo = world.spawn(contentsOf: saved)
    /// print(world.count)
    /// // Prints "4"
    ///
    /// let bravoFollower = bravo[follower]!
    /// print(world[Follows.self, of: bravoFollower].leader == bravo[leader])
    /// // Prints "true"
    /// print(alpha[leader] == bravo[leader])
    /// // Prints "false"
    /// ```
    ///
    /// Components are inserted as `insert(_:into:)` inserts them, running hooks.
    ///
    /// - Parameter scene: The scene whose entities to spawn.
    /// - Returns: The entity spawned for each live entity of the scene, keyed by the scene's
    ///   entity.
    /// - Complexity: O(*n*), where *n* is the number of entities and components spawned.
    @inlinable
    @discardableResult
    public mutating func spawn(contentsOf scene: Scene) -> [Entity: Entity] {
        var mapping: [Entity: Entity] = [:]
        var isVacant = [Bool](repeating: false, count: scene.generations.count)
        for slot in scene.vacant {
            isVacant[Int(slot)] = true
        }
        for slot in scene.generations.indices where !isVacant[slot] {
            mapping[Entity(index: UInt32(slot), generation: scene.generations[slot])] = spawn()
        }
        for family in scene.families {
            for child in family.children {
                link(mapping[child]!, to: mapping[family.parent]!)
            }
        }
        for (_, rows) in scene.components {
            rows.insert(into: &self, mapping: mapping)
        }
        for (_, value) in scene.resources {
            value.insert(into: &resources)
        }
        endOperation()
        return mapping
    }

    /// A world with the given slots and hierarchy and no components.
    @inlinable
    init(slots generations: [UInt32], vacant: [UInt32], families: [Family]) {
        self.init()
        self.generations = generations
        self.vacant = vacant
        isLive = [Bool](repeating: true, count: generations.count)
        for slot in vacant {
            isLive[Int(slot)] = false
        }
        for family in families {
            for child in family.children {
                storeRelation(ChildOf(), from: child, to: family.parent)
            }
        }
    }
}
