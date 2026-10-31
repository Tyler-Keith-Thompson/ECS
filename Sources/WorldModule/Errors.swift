/// An error that indicates an entity isn't live in the world.
///
/// The checked spellings of the world's entity operations, such as ``World/despawn(checked:)``
/// and ``World/insert(_:checkedInto:)``, throw this error when the entity was despawned or was
/// never spawned by the world. The world is unchanged when they throw:
///
/// ```swift
/// var world = World()
/// let spark = world.spawn(Position(x: 0, y: 0))
/// world.despawn(spark)
///
/// do {
///     try world.insert(Velocity(dx: 1, dy: 0), checkedInto: spark)
/// } catch {
///     print(error)
///     // Prints "StaleEntity()"
/// }
/// ```
@frozen
public struct StaleEntity: Error, Hashable, Sendable {
    /// Creates a stale entity error.
    @inlinable
    public init() {}
}

/// An error that indicates an entity holds no component of the requested type.
///
/// ``World/subscript(checked:of:)`` throws this error when the entity holds no component of the
/// type it reads. A stale entity holds none.
@frozen
public struct MissingComponent: Error, Hashable, Sendable {
    /// Creates a missing component error.
    @inlinable
    public init() {}
}

/// An error that indicates a world holds no resource of the requested type.
///
/// ``Resources/subscript(checked:)`` throws this error when the world holds no resource of the
/// type it reads.
@frozen
public struct MissingResource: Error, Hashable, Sendable {
    /// Creates a missing resource error.
    @inlinable
    public init() {}
}
