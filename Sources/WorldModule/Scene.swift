/// The component and resource types a ``Scene`` saves, each under a name that identifies it in
/// saved data.
///
/// Register each type once, then save whole worlds without listing types:
///
/// ```swift
/// var registry = TypeRegistry()
/// try registry.register(Position.self, named: "Position")
/// try registry.register(resource: Score.self, named: "Score")
/// let data = try JSONEncoder().encode(world.scene(registry))
///
/// let decoder = JSONDecoder()
/// decoder.userInfo[.typeRegistry] = registry
/// let restored = World(restoring: try decoder.decode(Scene.self, from: data))
/// ```
///
/// Relations other than ``ChildOf`` are saved by registering their ``Targets`` component, such as
/// `Targets<Likes>`.
@frozen
public struct TypeRegistry: Sendable {
    @usableFromInline var components: [ComponentRegistration] = []
    @usableFromInline var resources: [ResourceRegistration] = []

    /// An empty registry.
    @inlinable
    public init() {}

    /// The names of the registered component types, in the order they were registered.
    @inlinable
    public var componentNames: [String] { components.map(\.name) }

    /// The names of the registered resource types, in the order they were registered.
    @inlinable
    public var resourceNames: [String] { resources.map(\.name) }

    /// Registers the component type `C` under `name`, so scenes save its components.
    ///
    /// Registering a type again under the same name changes nothing.
    ///
    /// - Parameters:
    ///   - type: The component type.
    ///   - name: The name saved data identifies `C` by; by default the type's full name, such as
    ///     `"MyGame.Position"`. Give a name of your own to keep saved data readable after the type
    ///     or its module is renamed.
    /// - Throws: ``TypeRegistryError/nameTaken`` when another component type has `name`;
    ///   ``TypeRegistryError/typeAlreadyRegistered`` when `C` has another name. The registry is
    ///   unchanged.
    /// - Complexity: O(*t*) for *t* registered component types.
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

    /// Registers the resource type `R` under `name`, so scenes save it.
    ///
    /// Registering a type again under the same name changes nothing.
    ///
    /// - Parameters:
    ///   - type: The resource type.
    ///   - name: The name saved data identifies `R` by; by default the type's full name.
    /// - Throws: ``TypeRegistryError/nameTaken`` when another resource type has `name`;
    ///   ``TypeRegistryError/typeAlreadyRegistered`` when `R` has another name. The registry is
    ///   unchanged.
    /// - Complexity: O(*t*) for *t* registered resource types.
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

/// The error ``TypeRegistry`` registration throws, leaving the registry unchanged.
@frozen
public enum TypeRegistryError: Error, Hashable, Sendable {
    /// Another type of the same kind is registered under the name.
    case nameTaken
    /// The type is registered under another name.
    case typeAlreadyRegistered
}

extension CodingUserInfoKey {
    /// The key under which a decoder's `userInfo` holds the ``TypeRegistry`` a ``Scene`` is
    /// decoded with.
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
}

extension ComponentRows: SavedComponents {
    @inlinable
    var valueCount: Int { values.count }

    @inlinable
    func restore(into world: inout World) {
        world.restore(self)
    }
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

/// A world's entities, hierarchy, and the components and resources of the types a
/// ``TypeRegistry`` names, as a `Codable` value.
///
/// Take one with ``World/scene(_:)`` and rebuild a world from it with `World(restoring:)`. Every
/// entity handle, live or stale, means the same in the restored world, and the restored world
/// hands out the same handles from later spawns.
///
/// Encoding needs nothing more. Decoding needs the registry in the decoder's `userInfo` under
/// `CodingUserInfoKey.typeRegistry`, and throws `DecodingError.dataCorrupted` when it is
/// missing, when the data names a type the registry does not, or for data no world could have
/// produced. Types the registry names but the data does not are left out.
///
/// A scene holds no hooks, observers, caches, indexes or change ticks: the restored world's
/// components are all added at its first tick.
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
    /// The world's entities, hierarchy, and the components and resources of the types
    /// `registry` names.
    ///
    /// Components and resources of other types are left out.
    ///
    /// - Complexity: O(*n*) for *n* entities and components saved.
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

    /// The world `scene` was taken of, with its entities, hierarchy, and the components and
    /// resources it saved.
    ///
    /// - Complexity: O(*n*) for *n* entities and components restored.
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
