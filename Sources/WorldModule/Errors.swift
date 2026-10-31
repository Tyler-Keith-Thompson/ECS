/// The error a `checked:` operation throws when its entity was despawned or never spawned by the
/// world.
@frozen
public struct StaleEntity: Error, Hashable, Sendable {
    @inlinable
    public init() {}
}

/// The error ``World/subscript(checked:of:)`` throws when the entity holds no component of the
/// requested type. A stale entity holds none.
@frozen
public struct MissingComponent: Error, Hashable, Sendable {
    @inlinable
    public init() {}
}

/// The error ``Resources/subscript(checked:)`` throws when the world holds no resource of the
/// requested type.
@frozen
public struct MissingResource: Error, Hashable, Sendable {
    @inlinable
    public init() {}
}
