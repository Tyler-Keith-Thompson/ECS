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
        }, read: { world, entity in
            try? world[checked: C.self, of: entity]
        }, decodable: C.self, insert: { world, entity, decoded in
            guard let component = decoded as? C else {
                preconditionFailure("The decode closure returned a \(Swift.type(of: decoded)), not the \(C.self) it was asked for")
            }
            world.insert(component, into: entity)
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
        }, read: { resources in
            try? resources[checked: R.self]
        }, decodable: R.self, insert: { resources, decoded in
            guard let resource = decoded as? R else {
                preconditionFailure("The decode closure returned a \(Swift.type(of: decoded)), not the \(R.self) it was asked for")
            }
            resources.insert(resource)
        }))
    }
}

extension TypeRegistry {
    /// Returns the component of the type registered under a name that an entity holds.
    ///
    /// Use this method, with ``insert(componentNamed:into:in:decode:)``, to reach components by
    /// the names you registered them under rather than by their types, as a scripting host, a
    /// debugger or an inspector does. The component comes back as a `Codable` value, so you can
    /// encode it with any encoder:
    ///
    /// ```swift
    /// import Foundation
    ///
    /// var registry = TypeRegistry()
    /// try registry.register(Position.self, named: "Position")
    ///
    /// var world = World()
    /// let ship = world.spawn(Position(x: 3, y: 4))
    ///
    /// let position = registry.component(named: "Position", of: ship, in: world)
    /// let encoder = JSONEncoder()
    /// encoder.outputFormatting = .sortedKeys
    /// print(String(decoding: try encoder.encode(position), as: UTF8.self))
    /// // Prints "{"x":3,"y":4}"
    /// ```
    ///
    /// Inside your own `encode(to:)` method, write `try component.encode(to: encoder)`.
    ///
    /// - Parameters:
    ///   - name: The name the component type is registered under.
    ///   - entity: The entity that holds the component.
    ///   - world: The world the entity is in.
    /// - Returns: The component `entity` holds.
    /// - Precondition: A component type is registered under `name`, and `entity` is live and holds
    ///   a component of that type. The checked spelling,
    ///   ``component(checkedNamed:of:in:)``, throws instead.
    /// - Complexity: O(*t*), where *t* is the number of registered component types.
    @inlinable
    public func component(named name: String, of entity: Entity, in world: World) -> any Component & Codable {
        guard let registration = components.first(where: { $0.name == name }) else {
            preconditionFailure("No component type is registered as \(name)")
        }
        precondition(world.contains(entity), "Reading a \(name) of stale entity \(entity)")
        guard let component = registration.read(world, entity) else {
            preconditionFailure("Entity \(entity) holds no \(name)")
        }
        return component
    }

    /// Returns the component of the type registered under a name that an entity holds, throwing
    /// an error if there is none.
    ///
    /// Use this method when the name comes from outside your program, such as from a script:
    ///
    /// ```swift
    /// var registry = TypeRegistry()
    /// try registry.register(Position.self, named: "Position")
    ///
    /// var world = World()
    /// let ship = world.spawn(Position(x: 3, y: 4))
    ///
    /// do {
    ///     _ = try registry.component(checkedNamed: "Velocity", of: ship, in: world)
    /// } catch {
    ///     print(error)
    ///     // Prints "unregisteredName"
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name the component type is registered under.
    ///   - entity: The entity that holds the component.
    ///   - world: The world the entity is in.
    /// - Returns: The component `entity` holds.
    /// - Throws: ``TypeRegistryLookupError/unregisteredName`` if no component type is registered
    ///   under `name`, ``TypeRegistryLookupError/staleEntity`` if `entity` isn't live, or
    ///   ``TypeRegistryLookupError/missingValue`` if it holds no component of the type.
    /// - Complexity: O(*t*), where *t* is the number of registered component types.
    @inlinable
    public func component(checkedNamed name: String, of entity: Entity, in world: World) throws(TypeRegistryLookupError) -> any Component & Codable {
        guard let registration = components.first(where: { $0.name == name }) else { throw .unregisteredName }
        guard world.contains(entity) else { throw .staleEntity }
        guard let component = registration.read(world, entity) else { throw .missingValue }
        return component
    }

    /// Decodes a component of the type registered under a name and inserts it into an entity.
    ///
    /// The registry calls `decode` with the registered type; decode a value of that type from
    /// your data with any decoder. The following example sets a ship's position from JSON:
    ///
    /// ```swift
    /// import Foundation
    ///
    /// var registry = TypeRegistry()
    /// try registry.register(Position.self, named: "Position")
    ///
    /// var world = World()
    /// let ship = world.spawn()
    /// let data = Data(#"{"x": 5, "y": 6}"#.utf8)
    ///
    /// try registry.insert(componentNamed: "Position", into: ship, in: &world) { type in
    ///     try JSONDecoder().decode(type, from: data)
    /// }
    /// print(world[Position.self, of: ship])
    /// // Prints "Position(x: 5.0, y: 6.0)"
    /// ```
    ///
    /// Inside your own `init(from:)`, decode with `{ type in try type.init(from: decoder) }`. The
    /// component is inserted as `insert(_:into:)` inserts it, running hooks and adding the
    /// components it requires.
    ///
    /// - Parameters:
    ///   - name: The name the component type is registered under.
    ///   - entity: The entity to insert the component into.
    ///   - world: The world the entity is in.
    ///   - decode: A closure that decodes a value of the type it is passed.
    /// - Throws: Any error `decode` throws. The world is then unchanged.
    /// - Precondition: A component type is registered under `name`, `entity` is live, and
    ///   `decode` returns a value of the type it is passed. The checked spelling,
    ///   ``insert(componentNamed:checkedInto:in:decode:)``, throws for the first two instead.
    /// - Complexity: O(*t*) plus the cost of decoding, where *t* is the number of registered
    ///   component types.
    @inlinable
    public func insert(componentNamed name: String, into entity: Entity, in world: inout World, decode: (any Decodable.Type) throws -> any Decodable) rethrows {
        guard let registration = components.first(where: { $0.name == name }) else {
            preconditionFailure("No component type is registered as \(name)")
        }
        precondition(world.contains(entity), "Inserting a \(name) into stale entity \(entity)")
        registration.insert(&world, entity, try decode(registration.decodable))
    }

    /// Decodes a component of the type registered under a name and inserts it into an entity,
    /// throwing an error if the name isn't registered or the entity isn't live.
    ///
    /// See ``insert(componentNamed:into:in:decode:)``.
    ///
    /// - Parameters:
    ///   - name: The name the component type is registered under.
    ///   - entity: The entity to insert the component into.
    ///   - world: The world the entity is in.
    ///   - decode: A closure that decodes a value of the type it is passed.
    /// - Throws: ``TypeRegistryLookupError/unregisteredName`` if no component type is registered
    ///   under `name`, ``TypeRegistryLookupError/staleEntity`` if `entity` isn't live, or any
    ///   error `decode` throws. The world is then unchanged.
    /// - Precondition: `decode` returns a value of the type it is passed.
    /// - Complexity: O(*t*) plus the cost of decoding, where *t* is the number of registered
    ///   component types.
    @inlinable
    public func insert(componentNamed name: String, checkedInto entity: Entity, in world: inout World, decode: (any Decodable.Type) throws -> any Decodable) throws {
        guard let registration = components.first(where: { $0.name == name }) else { throw TypeRegistryLookupError.unregisteredName }
        guard world.contains(entity) else { throw TypeRegistryLookupError.staleEntity }
        registration.insert(&world, entity, try decode(registration.decodable))
    }

    /// Returns the resource of the type registered under a name.
    ///
    /// The resource comes back as a `Codable` value, so you can encode it with any encoder:
    ///
    /// ```swift
    /// import Foundation
    ///
    /// var registry = TypeRegistry()
    /// try registry.register(resource: Treasury.self, named: "Treasury")
    ///
    /// var world = World()
    /// world.resources.insert(Treasury(gold: 80))
    ///
    /// let treasury = registry.resource(named: "Treasury", in: world.resources)
    /// print(String(decoding: try JSONEncoder().encode(treasury), as: UTF8.self))
    /// // Prints "{"gold":80}"
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name the resource type is registered under.
    ///   - resources: The resources to read from.
    /// - Returns: The resource of the registered type.
    /// - Precondition: A resource type is registered under `name`, and `resources` holds a
    ///   resource of that type. The checked spelling, ``resource(checkedNamed:in:)``, throws
    ///   instead.
    /// - Complexity: O(*t*), where *t* is the number of registered resource types.
    @inlinable
    public func resource(named name: String, in resources: Resources) -> any Resource & Codable {
        guard let registration = self.resources.first(where: { $0.name == name }) else {
            preconditionFailure("No resource type is registered as \(name)")
        }
        guard let resource = registration.read(resources) else {
            preconditionFailure("No \(name) resource")
        }
        return resource
    }

    /// Returns the resource of the type registered under a name, throwing an error if there is
    /// none.
    ///
    /// - Parameters:
    ///   - name: The name the resource type is registered under.
    ///   - resources: The resources to read from.
    /// - Returns: The resource of the registered type.
    /// - Throws: ``TypeRegistryLookupError/unregisteredName`` if no resource type is registered
    ///   under `name`, or ``TypeRegistryLookupError/missingValue`` if `resources` holds none of
    ///   the type.
    /// - Complexity: O(*t*), where *t* is the number of registered resource types.
    @inlinable
    public func resource(checkedNamed name: String, in resources: Resources) throws(TypeRegistryLookupError) -> any Resource & Codable {
        guard let registration = self.resources.first(where: { $0.name == name }) else { throw .unregisteredName }
        guard let resource = registration.read(resources) else { throw .missingValue }
        return resource
    }

    /// Decodes a resource of the type registered under a name and inserts it, replacing any of
    /// the same type.
    ///
    /// The registry calls `decode` with the registered type; decode a value of that type from
    /// your data with any decoder:
    ///
    /// ```swift
    /// import Foundation
    ///
    /// var registry = TypeRegistry()
    /// try registry.register(resource: Treasury.self, named: "Treasury")
    ///
    /// var world = World()
    /// let data = Data(#"{"gold": 15}"#.utf8)
    /// try registry.insert(resourceNamed: "Treasury", into: &world.resources) { type in
    ///     try JSONDecoder().decode(type, from: data)
    /// }
    /// print(world.resources[Treasury.self].gold)
    /// // Prints "15"
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name the resource type is registered under.
    ///   - resources: The resources to insert into.
    ///   - decode: A closure that decodes a value of the type it is passed.
    /// - Throws: Any error `decode` throws. The resources are then unchanged.
    /// - Precondition: A resource type is registered under `name`, and `decode` returns a value
    ///   of the type it is passed. The checked spelling,
    ///   ``insert(resourceNamed:checkedInto:decode:)``, throws for the first instead.
    /// - Complexity: O(*t*) plus the cost of decoding, where *t* is the number of registered
    ///   resource types.
    @inlinable
    public func insert(resourceNamed name: String, into resources: inout Resources, decode: (any Decodable.Type) throws -> any Decodable) rethrows {
        guard let registration = self.resources.first(where: { $0.name == name }) else {
            preconditionFailure("No resource type is registered as \(name)")
        }
        registration.insert(&resources, try decode(registration.decodable))
    }

    /// Decodes a resource of the type registered under a name and inserts it, throwing an error
    /// if the name isn't registered.
    ///
    /// See ``insert(resourceNamed:into:decode:)``.
    ///
    /// - Parameters:
    ///   - name: The name the resource type is registered under.
    ///   - resources: The resources to insert into.
    ///   - decode: A closure that decodes a value of the type it is passed.
    /// - Throws: ``TypeRegistryLookupError/unregisteredName`` if no resource type is registered
    ///   under `name`, or any error `decode` throws. The resources are then unchanged.
    /// - Precondition: `decode` returns a value of the type it is passed.
    /// - Complexity: O(*t*) plus the cost of decoding, where *t* is the number of registered
    ///   resource types.
    @inlinable
    public func insert(resourceNamed name: String, checkedInto resources: inout Resources, decode: (any Decodable.Type) throws -> any Decodable) throws {
        guard let registration = self.resources.first(where: { $0.name == name }) else { throw TypeRegistryLookupError.unregisteredName }
        registration.insert(&resources, try decode(registration.decodable))
    }
}

/// An error that indicates why a ``TypeRegistry`` couldn't reach a component or resource by
/// name.
@frozen
public enum TypeRegistryLookupError: Error, Hashable, Sendable {
    /// No type of the kind asked for, component or resource, is registered under the name.
    case unregisteredName
    /// The entity isn't live.
    case staleEntity
    /// The entity holds no component of the registered type, or the resources hold no resource
    /// of it.
    case missingValue
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
    /// The component of this type an entity holds, if any.
    @usableFromInline let read: @Sendable (World, Entity) -> (any Component & Codable)?
    /// The registered type, to decode values of.
    @usableFromInline let decodable: any (Component & Codable).Type
    /// Inserts a decoded value of this type into the live entity; traps on a value of another
    /// type.
    @usableFromInline let insert: @Sendable (inout World, Entity, any Decodable) -> Void

    @inlinable
    init(name: String, type: ObjectIdentifier, capture: @escaping @Sendable (World) -> any SavedComponents, decode: @escaping @Sendable (KeyedDecodingContainer<SceneKey>, SceneKey) throws -> any SavedComponents, read: @escaping @Sendable (World, Entity) -> (any Component & Codable)?, decodable: any (Component & Codable).Type, insert: @escaping @Sendable (inout World, Entity, any Decodable) -> Void) {
        self.name = name
        self.type = type
        self.capture = capture
        self.decode = decode
        self.read = read
        self.decodable = decodable
        self.insert = insert
    }
}

/// A registered resource type: its name and how to save and decode it.
@usableFromInline
struct ResourceRegistration: Sendable {
    @usableFromInline let name: String
    @usableFromInline let type: ObjectIdentifier
    @usableFromInline let capture: @Sendable (World) -> (any SavedResourceValue)?
    @usableFromInline let decode: @Sendable (KeyedDecodingContainer<SceneKey>, SceneKey) throws -> any SavedResourceValue
    /// The resource of this type, if any.
    @usableFromInline let read: @Sendable (Resources) -> (any Resource & Codable)?
    /// The registered type, to decode values of.
    @usableFromInline let decodable: any (Resource & Codable).Type
    /// Inserts a decoded value of this type; traps on a value of another type.
    @usableFromInline let insert: @Sendable (inout Resources, any Decodable) -> Void

    @inlinable
    init(name: String, type: ObjectIdentifier, capture: @escaping @Sendable (World) -> (any SavedResourceValue)?, decode: @escaping @Sendable (KeyedDecodingContainer<SceneKey>, SceneKey) throws -> any SavedResourceValue, read: @escaping @Sendable (Resources) -> (any Resource & Codable)?, decodable: any (Resource & Codable).Type, insert: @escaping @Sendable (inout Resources, any Decodable) -> Void) {
        self.name = name
        self.type = type
        self.capture = capture
        self.decode = decode
        self.read = read
        self.decodable = decodable
        self.insert = insert
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
