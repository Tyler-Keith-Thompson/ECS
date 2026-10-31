/// A type that groups components to be spawned, inserted, and removed together.
///
/// Use a bundle to name a set of components that often go together, such as everything a ship
/// needs, so you can spawn them in one step and keep that set in one place. Declare the
/// bundle's contents in its ``body-9bv1p`` property. The body is built by ``BundleBuilder``, so you
/// can list components and other bundles, and use `if`, `switch` and optional values:
///
/// ```swift
/// struct Armor: Component { var rating: Int }
///
/// struct Ship: Bundle {
///     var position: Position
///     var armored: Bool
///
///     var body: some Bundle {
///         position
///         Velocity(dx: 0, dy: 0)
///         if armored { Armor(rating: 10) }
///     }
/// }
///
/// var world = World()
/// let ship = world.spawn(Ship(position: Position(x: 0, y: 0), armored: true))
/// print(world.contains(Armor.self, in: ship))
/// // Prints "true"
/// ```
///
/// Removing a bundle type removes every component type the bundle can hold, including the types
/// of branches that weren't taken:
///
/// ```swift
/// var world = World()
/// let ship = world.spawn(
///     Ship(position: Position(x: 0, y: 0), armored: false),
///     Health(current: 50)
/// )
///
/// world.remove(Ship.self, from: ship)
/// print(world.contains(Position.self, in: ship), world.contains(Health.self, in: ship))
/// // Prints "false true"
/// ```
///
/// Every ``Component`` is a bundle of itself, so anywhere a bundle is expected, you can pass a
/// single component.
///
/// - Note: Foundation also declares a type named `Bundle`. In a file that imports Foundation,
///   write `ECS.Bundle` to name this protocol.
public protocol Bundle: Sendable {
    /// The type of the bundle this bundle is made of.
    associatedtype Body: Bundle

    /// The components and bundles this bundle is made of.
    ///
    /// Implement this property to list the bundle's contents. A component has no body: it is a
    /// bundle of itself.
    @BundleBuilder var body: Body { get }

    /// Adds this bundle's components to an entity, replacing any it holds of the same types.
    ///
    /// The world calls this method when it spawns or inserts the bundle, and runs the hooks the
    /// insertion fires once it finishes. You don't need to implement or call it: the default
    /// implementation inserts the contents of ``Bundle/body-9bv1p``. To add a bundle to an
    /// entity, call ``World/insert(_:into:)-70968``.
    ///
    /// - Parameters:
    ///   - entity: The entity to add the components to.
    ///   - world: The world that holds the entity.
    /// - Precondition: `entity` is live.
    func insert(into entity: Entity, in world: inout World)

    /// Removes from an entity every component type this bundle can hold.
    ///
    /// The world calls this method when it removes the bundle, and runs the hooks the removal
    /// fires once it finishes. You don't need to implement or call it: the default implementation
    /// removes the types of ``Bundle/body-9bv1p``. To remove a bundle from an entity, call
    /// ``World/remove(_:from:)-9j0yg``.
    ///
    /// - Parameters:
    ///   - entity: The entity to remove the components from.
    ///   - world: The world that holds the entity.
    /// - Precondition: `entity` is live.
    static func remove(from entity: Entity, in world: inout World)

    /// Whether a component this bundle can hold requires others.
    @_documentation(visibility: internal)
    static var _hasRequirements: Bool { get }

    /// Gives `entity` the components its components in this bundle require, of the types it
    /// does not hold; called after every bundle of a spawn or insertion is inserted.
    @_documentation(visibility: internal)
    func _insertRequired(into entity: Entity, in world: inout World)

    /// Gives `entity` this bundle's components of the types it does not hold, and what they
    /// require.
    @_documentation(visibility: internal)
    func _insertMissing(into entity: Entity, in world: inout World)
}

extension Bundle {
    @inlinable
    public func insert(into entity: Entity, in world: inout World) {
        body.insert(into: entity, in: &world)
    }

    @inlinable
    public static func remove(from entity: Entity, in world: inout World) {
        Body.remove(from: entity, in: &world)
    }

    @_documentation(visibility: internal)
    @inlinable
    public static var _hasRequirements: Bool { Body._hasRequirements }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertRequired(into entity: Entity, in world: inout World) {
        guard Self._hasRequirements else { return }
        body._insertRequired(into: entity, in: &world)
    }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertMissing(into entity: Entity, in world: inout World) {
        body._insertMissing(into: entity, in: &world)
    }
}

extension Component {
    /// A component has no body, because it is a bundle of itself; reading this property traps.
    public var body: Never {
        return preconditionFailure("A component is a bundle of itself and has no body")
    }

    @inlinable
    public func insert(into entity: Entity, in world: inout World) {
        precondition(world.contains(entity), "Inserting into stale entity \(entity)")
        world.store(self, for: entity)
    }

    @inlinable
    public static func remove(from entity: Entity, in world: inout World) {
        precondition(world.contains(entity), "Removing a \(Self.self) from stale entity \(entity)")
        _ = world.discard(Self.self, from: entity)
    }

    @_documentation(visibility: internal)
    @inlinable
    public static var _hasRequirements: Bool { true }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertRequired(into entity: Entity, in world: inout World) {
        guard Self._hasRequirements else { return }
        Self.required._insertMissing(into: entity, in: &world)
    }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertMissing(into entity: Entity, in world: inout World) {
        guard !world.contains(Self.self, in: entity) else { return }
        world.store(self, for: entity)
        if Self._hasRequirements {
            Self.required._insertMissing(into: entity, in: &world)
        }
    }
}

extension Never: Bundle {
    public var body: Never {
        return preconditionFailure("Never has no body")
    }

    public func insert(into entity: Entity, in world: inout World) {}

    public static func remove(from entity: Entity, in world: inout World) {}

    @_documentation(visibility: internal)
    public static var _hasRequirements: Bool { false }

    @_documentation(visibility: internal)
    public func _insertRequired(into entity: Entity, in world: inout World) {}

    @_documentation(visibility: internal)
    public func _insertMissing(into entity: Entity, in world: inout World) {}
}

/// A result builder that creates a bundle from the components and bundles listed in a closure.
///
/// You use a bundle builder by implementing a bundle's ``Bundle/body-9bv1p`` property or a
/// component's ``Component/required-u15k`` property. Write one component or bundle per line;
/// `if`, `if`-`else`, `switch` and `if let` choose what to include.
@resultBuilder
public enum BundleBuilder {
    /// Builds an empty bundle from an empty block.
    @inlinable
    public static func buildBlock() -> TupleBundle< > { TupleBundle() }

    /// Builds a bundle from the bundles listed in a block, in order.
    @inlinable
    public static func buildBlock<each B: Bundle>(_ bundles: repeat each B) -> TupleBundle<repeat each B> {
        TupleBundle(repeat each bundles)
    }

    /// Builds an optional bundle from an `if` statement without an `else`.
    @inlinable
    public static func buildOptional<B: Bundle>(_ bundle: B?) -> B? { bundle }

    /// Builds a bundle from the first branch of an `if`-`else` or `switch` statement.
    @inlinable
    public static func buildEither<First: Bundle, Second: Bundle>(first bundle: First) -> EitherBundle<First, Second> {
        .first(bundle)
    }

    /// Builds a bundle from the second branch of an `if`-`else` or `switch` statement.
    @inlinable
    public static func buildEither<First: Bundle, Second: Bundle>(second bundle: Second) -> EitherBundle<First, Second> {
        .second(bundle)
    }
}

/// A bundle made of other bundles, inserted in order.
///
/// A ``BundleBuilder`` creates a tuple bundle from the lines of a block. Because the bundles are
/// inserted in order, a later component replaces an earlier one of the same type.
@frozen
public struct TupleBundle<each B: Bundle>: Bundle {
    @usableFromInline let bundles: (repeat each B)

    /// Creates a bundle of the given bundles.
    ///
    /// - Parameter bundles: The bundles to insert, in order.
    @inlinable
    public init(_ bundles: repeat each B) {
        self.bundles = (repeat each bundles)
    }

    /// A tuple bundle has no body; reading this property traps.
    public var body: Never {
        return preconditionFailure("A tuple bundle has no body")
    }

    @inlinable
    public func insert(into entity: Entity, in world: inout World) {
        for bundle in repeat each bundles {
            bundle.insert(into: entity, in: &world)
        }
    }

    @inlinable
    public static func remove(from entity: Entity, in world: inout World) {
        for type in repeat (each B).self {
            type.remove(from: entity, in: &world)
        }
    }

    @_documentation(visibility: internal)
    @inlinable
    public static var _hasRequirements: Bool {
        for type in repeat (each B).self {
            if type._hasRequirements { return true }
        }
        return false
    }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertRequired(into entity: Entity, in world: inout World) {
        guard Self._hasRequirements else { return }
        for bundle in repeat each bundles {
            bundle._insertRequired(into: entity, in: &world)
        }
    }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertMissing(into entity: Entity, in world: inout World) {
        for bundle in repeat each bundles {
            bundle._insertMissing(into: entity, in: &world)
        }
    }
}

/// A bundle that holds one of two bundles, from an `if`-`else` or `switch` statement.
///
/// A ``BundleBuilder`` creates an either bundle from a branching statement. Inserting it inserts
/// the branch that was taken; removing its type removes the component types of both branches.
@frozen
public enum EitherBundle<First: Bundle, Second: Bundle>: Bundle {
    /// The bundle of the first branch.
    case first(First)
    /// The bundle of the second branch.
    case second(Second)

    /// An either bundle has no body; reading this property traps.
    public var body: Never {
        return preconditionFailure("An either bundle has no body")
    }

    @inlinable
    public func insert(into entity: Entity, in world: inout World) {
        switch self {
        case let .first(bundle): bundle.insert(into: entity, in: &world)
        case let .second(bundle): bundle.insert(into: entity, in: &world)
        }
    }

    @inlinable
    public static func remove(from entity: Entity, in world: inout World) {
        First.remove(from: entity, in: &world)
        Second.remove(from: entity, in: &world)
    }

    @_documentation(visibility: internal)
    @inlinable
    public static var _hasRequirements: Bool { First._hasRequirements || Second._hasRequirements }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertRequired(into entity: Entity, in world: inout World) {
        switch self {
        case let .first(bundle): bundle._insertRequired(into: entity, in: &world)
        case let .second(bundle): bundle._insertRequired(into: entity, in: &world)
        }
    }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertMissing(into entity: Entity, in world: inout World) {
        switch self {
        case let .first(bundle): bundle._insertMissing(into: entity, in: &world)
        case let .second(bundle): bundle._insertMissing(into: entity, in: &world)
        }
    }
}

extension Optional: Bundle where Wrapped: Bundle {
    public var body: Never {
        return preconditionFailure("An optional bundle has no body")
    }

    /// Adds the wrapped bundle's components to an entity, or nothing if the optional is `nil`.
    @inlinable
    public func insert(into entity: Entity, in world: inout World) {
        if let bundle = self {
            bundle.insert(into: entity, in: &world)
        }
    }

    @inlinable
    public static func remove(from entity: Entity, in world: inout World) {
        Wrapped.remove(from: entity, in: &world)
    }

    @_documentation(visibility: internal)
    @inlinable
    public static var _hasRequirements: Bool { Wrapped._hasRequirements }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertRequired(into entity: Entity, in world: inout World) {
        self?._insertRequired(into: entity, in: &world)
    }

    @_documentation(visibility: internal)
    @inlinable
    public func _insertMissing(into entity: Entity, in world: inout World) {
        self?._insertMissing(into: entity, in: &world)
    }
}

extension World {
    /// Removes from an entity every component type a bundle can hold.
    ///
    /// Use this method to undo spawning or inserting a bundle. It removes the types of every
    /// branch of the bundle's body, including branches that weren't taken, and leaves the
    /// entity's other components in place. See ``Bundle`` for an example.
    ///
    /// - Parameters:
    ///   - type: The bundle type whose component types to remove.
    ///   - entity: The entity to remove them from.
    /// - Complexity: O(*k*), where *k* is the number of component types the bundle can hold.
    /// - Precondition: `entity` is live. The checked spelling, ``remove(_:checkedFrom:)-9ksld``,
    ///   throws instead.
    @inlinable
    public mutating func remove<B: Bundle>(_ type: B.Type, from entity: Entity) {
        precondition(contains(entity), "Removing a \(B.self) from stale entity \(entity)")
        B.remove(from: entity, in: &self)
        endOperation()
    }

    /// Removes from an entity every component type a bundle can hold, throwing an error if the
    /// entity isn't live.
    ///
    /// - Parameters:
    ///   - type: The bundle type whose component types to remove.
    ///   - entity: The entity to remove them from.
    /// - Throws: ``StaleEntity`` if `entity` isn't live. The world is unchanged.
    /// - Complexity: O(*k*), where *k* is the number of component types the bundle can hold.
    @inlinable
    public mutating func remove<B: Bundle>(_ type: B.Type, checkedFrom entity: Entity) throws(StaleEntity) {
        guard contains(entity) else { throw StaleEntity() }
        B.remove(from: entity, in: &self)
        endOperation()
    }
}

extension Commands {
    /// Records removing from an entity every component type a bundle can hold.
    ///
    /// When the command applies, nothing happens if `entity` isn't live.
    ///
    /// - Parameters:
    ///   - type: The bundle type whose component types to remove.
    ///   - entity: The entity to remove them from, or a handle that an earlier ``spawn(_:)``
    ///     command in this buffer returned.
    @inlinable
    public mutating func remove<B: Bundle>(_ type: B.Type, from entity: Entity) {
        operations.append { world, spawned in try? world.remove(B.self, checkedFrom: Self.resolve(entity, in: spawned)) }
    }
}
