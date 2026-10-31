/// Components that go together, spawned, inserted and removed as one.
///
/// A bundle lists its components in ``body``, built by ``BundleBuilder``: components, other
/// bundles, `if`, `switch` and optional values. Every ``Component`` is a bundle of itself.
///
/// ```swift
/// struct Ship: Bundle {
///     var position: Position
///     var armored: Bool
///
///     var body: some Bundle {
///         position
///         Velocity(dx: 0, dy: 0)
///         if armored { Armor(10) }
///     }
/// }
///
/// let ship = world.spawn(Ship(position: Position(x: 0, y: 0), armored: true))
/// world.remove(Ship.self, from: ship)  // takes away Position, Velocity and Armor
/// ```
public protocol Bundle: Sendable {
    /// The bundle this one is made of.
    associatedtype Body: Bundle

    /// The components and bundles this bundle is made of.
    @BundleBuilder var body: Body { get }

    /// Gives `entity` this bundle's components, replacing any it holds of the same types.
    ///
    /// ``World/spawn(_:)`` and ``World/insert(_:into:)`` call this, and run the hooks it fires
    /// when they finish.
    ///
    /// - Precondition: `entity` is live.
    func insert(into entity: Entity, in world: inout World)

    /// Takes away from `entity` every component type this bundle can hold.
    ///
    /// ``World/remove(_:from:)`` calls this, and runs the hooks it fires when it finishes.
    ///
    /// - Precondition: `entity` is live.
    static func remove(from entity: Entity, in world: inout World)
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
}

extension Component {
    /// A component has no body: it is a bundle of itself.
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
}

extension Never: Bundle {
    public var body: Never {
        return preconditionFailure("Never has no body")
    }

    public func insert(into entity: Entity, in world: inout World) {}

    public static func remove(from entity: Entity, in world: inout World) {}
}

/// Builds a bundle from the components and bundles written in a block.
@resultBuilder
public enum BundleBuilder {
    @inlinable
    public static func buildBlock() -> TupleBundle< > { TupleBundle() }

    @inlinable
    public static func buildBlock<each B: Bundle>(_ bundles: repeat each B) -> TupleBundle<repeat each B> {
        TupleBundle(repeat each bundles)
    }

    @inlinable
    public static func buildOptional<B: Bundle>(_ bundle: B?) -> B? { bundle }

    @inlinable
    public static func buildEither<First: Bundle, Second: Bundle>(first bundle: First) -> EitherBundle<First, Second> {
        .first(bundle)
    }

    @inlinable
    public static func buildEither<First: Bundle, Second: Bundle>(second bundle: Second) -> EitherBundle<First, Second> {
        .second(bundle)
    }
}

/// Bundles written one after another: each inserted in order, so a later component replaces an
/// earlier one of the same type.
@frozen
public struct TupleBundle<each B: Bundle>: Bundle {
    @usableFromInline let bundles: (repeat each B)

    @inlinable
    public init(_ bundles: repeat each B) {
        self.bundles = (repeat each bundles)
    }

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
}

/// One of two bundles, from an `if`–`else` or a `switch`; removing it removes the types of both.
@frozen
public enum EitherBundle<First: Bundle, Second: Bundle>: Bundle {
    case first(First)
    case second(Second)

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
}

extension Optional: Bundle where Wrapped: Bundle {
    public var body: Never {
        return preconditionFailure("An optional bundle has no body")
    }

    /// Gives `entity` the wrapped bundle's components, or nothing when there is none.
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
}

extension World {
    /// Takes away from `entity` every component type a `B` can hold.
    ///
    /// - Complexity: O(*k*) for *k* component types.
    /// - Precondition: `entity` is live. Use ``remove(_:checkedFrom:)`` to throw instead.
    @inlinable
    public mutating func remove<B: Bundle>(_ type: B.Type, from entity: Entity) {
        precondition(contains(entity), "Removing a \(B.self) from stale entity \(entity)")
        B.remove(from: entity, in: &self)
        endOperation()
    }

    /// Takes away from `entity` every component type a `B` can hold.
    ///
    /// - Complexity: O(*k*) for *k* component types.
    /// - Throws: ``StaleEntity`` when `entity` is not live; the world is unchanged.
    @inlinable
    public mutating func remove<B: Bundle>(_ type: B.Type, checkedFrom entity: Entity) throws(StaleEntity) {
        guard contains(entity) else { throw StaleEntity() }
        B.remove(from: entity, in: &self)
        endOperation()
    }
}

extension Commands {
    /// Records taking away from `entity` every component type a `B` can hold.
    @inlinable
    public mutating func remove<B: Bundle>(_ type: B.Type, from entity: Entity) {
        operations.append { world, spawned in try? world.remove(B.self, checkedFrom: Self.resolve(entity, in: spawned)) }
    }
}
