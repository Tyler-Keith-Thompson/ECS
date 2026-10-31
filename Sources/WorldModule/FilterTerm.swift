/// A type that stands for a query filter, so a system's parameter can name the filter in its type.
///
/// A system declares what it reads through the types of its parameters, so it can't pass a
/// ``QueryFilter`` value. Instead it lists filter types in ``Query/Where``, such as
/// `Query<Health>.Where<Changed<Health>, Without<Frozen>>`. Each filter type stands for one
/// ``QueryFilter``:
///
/// | Filter type | Filter |
/// |---|---|
/// | ``With`` | ``QueryFilter/with(_:)-swift.type.method`` |
/// | ``Without`` | ``QueryFilter/without(_:)-swift.type.method`` |
/// | ``Added`` | ``QueryFilter/added(_:since:)-swift.type.method`` |
/// | ``Changed`` | ``QueryFilter/changed(_:since:)-swift.type.method`` |
/// | ``Allows`` | ``QueryFilter/allowing(_:)-swift.type.method`` |
/// | ``AnyOf`` of filter types | ``QueryFilter/anyOf(_:)-swift.type.method`` |
///
/// ``Added`` and ``Changed`` compare against the world's ``World/lastRun``, so a system sees what
/// was added or changed since its previous run.
public protocol FilterTerm: Sendable {
    /// The filter that this type stands for.
    static var filter: QueryFilter { get }

    /// `access`, also reading every component type this filter reads.
    @_documentation(visibility: internal)
    static func _reading(_ access: Access) -> Access
}

/// A filter type that passes the entities holding a component of type `C`.
///
/// `With<C>` stands for ``QueryFilter/with(_:)-swift.type.method``.
@frozen
public struct With<C: Component>: FilterTerm {
    public static var filter: QueryFilter { .with(C.self) }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access { access.reads(C.self) }
}

/// A filter type that passes the entities holding no component of type `C`.
///
/// `Without<C>` stands for ``QueryFilter/without(_:)-swift.type.method``.
@frozen
public struct Without<C: Component>: FilterTerm {
    public static var filter: QueryFilter { .without(C.self) }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access { access.reads(C.self) }
}

/// A filter type that passes the entities whose component of type `C` was added since the
/// world's last run.
///
/// `Added<C>` stands for ``QueryFilter/added(_:since:)-swift.type.method`` with no tick, so it
/// compares against ``World/lastRun``: in a system, the entities that gained a `C` since the
/// system's previous run.
@frozen
public struct Added<C: Component>: FilterTerm {
    public static var filter: QueryFilter { .added(C.self) }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access { access.reads(C.self) }
}

/// A filter type that passes the entities whose component of type `C` was added or changed since
/// the world's last run.
///
/// `Changed<C>` stands for ``QueryFilter/changed(_:since:)-swift.type.method`` with no tick, so
/// it compares against ``World/lastRun``: in a system, the entities whose `C` was added or changed
/// since the system's previous run.
@frozen
public struct Changed<C: Component>: FilterTerm {
    public static var filter: QueryFilter { .changed(C.self) }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access { access.reads(C.self) }
}

/// A filter type that also passes the entities holding a disabling component of type `C`.
///
/// A query skips entities that hold a disabling component, such as ``Disabled``, unless it names
/// the type. `Allows<C>` stands for ``QueryFilter/allowing(_:)-swift.type.method``.
@frozen
public struct Allows<C: Component>: FilterTerm {
    public static var filter: QueryFilter { .allowing(C.self) }

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access { access.reads(C.self) }
}

extension AnyOf: FilterTerm where repeat each C: FilterTerm {
    /// A filter that passes the entities that pass at least one of the filter types.
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
