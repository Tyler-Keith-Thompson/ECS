/// Component types an entity must hold, and types it must not, beyond the ones a query reads.
///
/// Filters compose: each modifier returns a new filter.
///
/// ```swift
/// let living = QueryFilter.with(Player.self).without(Dead.self)
/// ```
@frozen
public struct QueryFilter: Hashable, Sendable {
    @usableFromInline var required: [ObjectIdentifier] = []
    @usableFromInline var excluded: [ObjectIdentifier] = []

    /// A filter that passes every entity.
    @inlinable
    public init() {}

    /// A filter that passes entities holding every one of `types`.
    @inlinable
    public static func with<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        QueryFilter().with(repeat each types)
    }

    /// A filter that passes entities holding none of `types`.
    @inlinable
    public static func without<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        QueryFilter().without(repeat each types)
    }

    /// This filter, also requiring every one of `types`.
    @inlinable
    public func with<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        var filter = self
        for type in repeat each types {
            filter.required.append(ObjectIdentifier(type))
        }
        return filter
    }

    /// This filter, also excluding each of `types`.
    @inlinable
    public func without<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        var filter = self
        for type in repeat each types {
            filter.excluded.append(ObjectIdentifier(type))
        }
        return filter
    }
}

/// A filter resolved against one world: the indexes of its required and excluded columns.
@frozen
@usableFromInline
struct ResolvedFilter: Sendable {
    @usableFromInline let required: [SparseIndex]
    @usableFromInline let excluded: [SparseIndex]
    /// Whether some required type has no column, so nothing passes.
    @usableFromInline let isUnsatisfiable: Bool

    @inlinable
    init(_ filter: QueryFilter, in world: World) {
        var required: [SparseIndex] = []
        var isUnsatisfiable = false
        for type in filter.required {
            if let slot = world.columnPositions.position(of: type) {
                required.append(world.columns[slot].index)
            } else {
                isUnsatisfiable = true
            }
        }
        self.required = required
        self.excluded = filter.excluded.compactMap { type in world.columnPositions.position(of: type).map { world.columns[$0].index } }
        self.isUnsatisfiable = isUnsatisfiable
    }

    /// Whether `entity` holds every required type and no excluded one.
    @inlinable
    func passes(_ entity: Entity) -> Bool {
        for index in required where index.position(of: entity) == nil { return false }
        for index in excluded where index.position(of: entity) != nil { return false }
        return true
    }

    /// Whether the filter passes every entity, so checking it can be skipped.
    @inlinable
    var isEmpty: Bool { required.isEmpty && excluded.isEmpty }
}
