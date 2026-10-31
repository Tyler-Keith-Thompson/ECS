/// A condition on an entity, written as a type: the filters of a ``Query/Where`` and of a
/// system's parameters.
///
/// Each filter type mirrors a ``QueryFilter`` value: ``With`` is `.with`, ``Without`` is
/// `.without`, ``Added`` is `.added`, ``Changed`` is `.changed`, and ``AnyOf`` of filter types
/// is `.anyOf`.
public protocol FilterTerm: Sendable {
    /// The filter this type stands for.
    static var filter: QueryFilter { get }

    /// `access`, also reading every component type this filter reads.
    @_documentation(visibility: internal)
    static func _reading(_ access: Access) -> Access
}

/// Passes entities holding a `C`; the type of ``QueryFilter/with(_:)-swift.type.method``.
@frozen
public struct With<C: Component>: FilterTerm {
    public static var filter: QueryFilter { .with(C.self) }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access { access.reads(C.self) }
}

/// Passes entities holding no `C`; the type of ``QueryFilter/without(_:)-swift.type.method``.
@frozen
public struct Without<C: Component>: FilterTerm {
    public static var filter: QueryFilter { .without(C.self) }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access { access.reads(C.self) }
}

/// Passes entities whose `C` was added since the world's ``World/lastRun``; the type of
/// ``QueryFilter/added(_:since:)-swift.type.method``.
@frozen
public struct Added<C: Component>: FilterTerm {
    public static var filter: QueryFilter { .added(C.self) }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access { access.reads(C.self) }
}

/// Passes entities whose `C` was added or changed since the world's ``World/lastRun``; the type
/// of ``QueryFilter/changed(_:since:)-swift.type.method``.
@frozen
public struct Changed<C: Component>: FilterTerm {
    public static var filter: QueryFilter { .changed(C.self) }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access { access.reads(C.self) }
}

extension AnyOf: FilterTerm where repeat each C: FilterTerm {
    /// Passes entities that at least one of the filter types passes.
    public static var filter: QueryFilter {
        var filters: [QueryFilter] = []
        for type in repeat (each C).self {
            filters.append(type.filter)
        }
        return QueryFilter().anyOf(filters)
    }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access {
        var access = access
        for type in repeat (each C).self {
            access = type._reading(access)
        }
        return access
    }
}
