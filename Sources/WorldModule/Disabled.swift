/// A component that makes queries and updates skip an entity, unless they ask for it.
///
/// Use this component to take an entity out of play for a while without despawning it, such as
/// an enemy waiting off screen. A disabled entity keeps its components and stays live, and
/// reading it directly through its handle still works. A query or update reaches it only when it
/// reads or writes `Disabled`, names it in a filter, or allows it with
/// ``QueryFilter/allowing(_:)-swift.type.method``:
///
/// ```swift
/// var world = World()
/// world.spawn(Position(x: 0, y: 0))
/// let enemy = world.spawn(Position(x: 5, y: 5))
///
/// world.insert(Disabled(), into: enemy)
/// print(world.query(Position.self).count)
/// // Prints "1"
/// print(world.query(Position.self).allowing(Disabled.self).count)
/// // Prints "2"
///
/// world.remove(Disabled.self, from: enemy)
/// print(world.query(Position.self).count)
/// // Prints "2"
/// ```
///
/// To make your own component types behave like `Disabled`, register them with
/// ``World/registerDisablingComponent(_:)``.
@frozen
public struct Disabled: Component, Hashable {
    /// Creates a disabled mark.
    @inlinable
    public init() {}
}

extension World {
    /// Makes queries and updates skip the entities holding a component of the given type, as
    /// they skip ``Disabled`` entities.
    ///
    /// A query or update still reaches those entities when it reads or writes the type, names it
    /// in a filter, or allows it with ``QueryFilter/allowing(_:)-swift.type.method``:
    ///
    /// ```swift
    /// struct Hidden: Component {}
    ///
    /// var world = World()
    /// world.registerDisablingComponent(Hidden.self)
    /// world.spawn(Position(x: 0, y: 0))
    /// world.spawn(Position(x: 1, y: 1), Hidden())
    ///
    /// print(world.query(Position.self).count)
    /// // Prints "1"
    /// ```
    ///
    /// Registering a type twice changes nothing.
    ///
    /// - Parameter type: The component type whose entities queries skip.
    /// - Complexity: O(*d*), where *d* is the number of component types registered this way.
    @inlinable
    public mutating func registerDisablingComponent<C: Component>(_ type: C.Type) {
        guard !disablingComponents.contains(ObjectIdentifier(C.self)) else { return }
        disablingComponents.append(ObjectIdentifier(C.self))
    }
}
