import WorldModule

/// A value a system's `run` takes instead of the whole world, whose type states what it reads
/// and writes.
///
/// `@System` builds a system's ``System/access`` from its parameters' types and fetches them
/// before each run. The parameters are ``WorldModule/Query`` and ``WorldModule/Query/Where`` for
/// reading components, ``Update`` for writing them, ``ResourceReader`` and ``ResourceWriter``,
/// ``EventReader`` and ``EventWriter``, and `inout` ``WorldModule/Commands`` for structural
/// changes, which conflict with nothing and apply at the end of the group the system runs in.
public protocol SystemParameter {
    /// What the parameter reads and writes, as a parameter of a system of type `system`.
    static func _access<S>(in system: S.Type) -> Access
}

/// The access of a system's parameters, every one, trapping if two conflict.
///
/// - Precondition: No parameter writes a type another reads or writes.
@inlinable
public func _parameterAccess(_ accesses: Access...) -> Access {
    for first in accesses.indices {
        for second in accesses.indices where second > first {
            precondition(!accesses[first].conflicts(with: accesses[second]), "Parameters \(first) and \(second) of a system conflict: one writes what the other reads or writes")
        }
    }
    return accesses.reduce(Access()) { $0.merging($1) }
}

// MARK: Reading components

extension Query: SystemParameter {
    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        var access = Access()
        for type in repeat (each T).self {
            access = type._reading(access)
        }
        return access
    }

    /// The query of this type, bound to `world`'s rows through `query`, which a call site that
    /// knows the terms' types writes as `{ world, query in world.query(query) }` so the rows are
    /// read by the overload for the query's shape.
    @inlinable
    public static func _fetch(
        from world: World, query: (World, Query) -> QueryView<repeat (each T).Value>
    ) -> Query {
        let unbound = Query(filter: QueryFilter())
        return unbound._bound(to: query(world, unbound))
    }

    /// The query of this type, bound to `world`.
    @inlinable
    public static func _fetch(from world: World) -> Query {
        _fetch(from: world) { world, query in world.query(query) }
    }
}

extension Query.Where: SystemParameter {
    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        var access = Query._access(in: system)
        for type in repeat (each F).self {
            access = type._reading(access)
        }
        return access
    }

    /// The query of this type with its filter, bound to `world`'s rows through `query`; see
    /// ``WorldModule/Query/_fetch(from:query:)``.
    @inlinable
    public static func _fetch(
        from world: World, query: (World, Query) -> QueryView<repeat (each T).Value>
    ) -> Query.Where<repeat each F> {
        let unbound = Query(filter: filter)
        return Query.Where(_bound: unbound._bound(to: query(world, unbound)))
    }

    /// The query of this type with its filter, bound to `world`.
    @inlinable
    public static func _fetch(from world: World) -> Query.Where<repeat each F> {
        _fetch(from: world) { world, query in world.query(query) }
    }
}

// MARK: Resources

/// Reads the resource `R`.
@frozen
public struct ResourceReader<R: Resource>: SystemParameter, Sendable {
    /// The resource, as it was when the system started.
    public let value: R

    @inlinable
    init(value: R) {
        self.value = value
    }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        .reads(resources: R.self)
    }

    /// The resource of `world`.
    ///
    /// - Precondition: `world` holds an `R`.
    @inlinable
    public static func _fetch(from world: World) -> ResourceReader {
        ResourceReader(value: world.resources[R.self])
    }
}

/// Reads and writes the resource `R`.
public final class ResourceWriter<R: Resource>: SystemParameter, @unchecked Sendable {
    @usableFromInline var part: World

    @inlinable
    init(part: World) {
        self.part = part
    }

    /// The resource, changed in place.
    ///
    /// - Precondition: The world holds an `R`.
    @inlinable
    public var value: R {
        get { part.resources[R.self] }
        set { part.resources[R.self] = newValue }
        _modify { yield &part.resources[R.self] }
    }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        .writes(resources: R.self)
    }

    /// Takes the resource out of `world` until ``_restore(into:)``.
    @inlinable
    public static func _fetch(from world: inout World) -> ResourceWriter {
        ResourceWriter(part: world.split(writing: _access(in: Self.self)))
    }

    /// Puts the resource back into `world`.
    @inlinable
    public func _restore(into world: inout World) {
        world.merge(writing: Self._access(in: Self.self), from: part)
    }
}

// MARK: Events

/// Reads the events of type `E` sent since the system last read them.
@frozen
public struct EventReader<E: Event>: SystemParameter, RandomAccessCollection, Sendable {
    /// The events, oldest first.
    public let events: EventsView<E>

    @inlinable
    init(events: EventsView<E>) {
        self.events = events
    }

    @inlinable
    public var startIndex: Int { events.startIndex }
    @inlinable
    public var endIndex: Int { events.endIndex }
    @inlinable
    public subscript(position: Int) -> E { events[position] }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        .readsEvents(E.self, by: S.self)
    }

    /// The events `world` holds that a system of type `system` has not read, marking them read.
    @inlinable
    public static func _fetch<S>(from world: inout World, system: S.Type) -> EventReader {
        EventReader(events: world.readEvents(E.self, by: S.self))
    }
}

/// Sends events of type `E`.
public final class EventWriter<E: Event>: SystemParameter, @unchecked Sendable {
    @usableFromInline var part: World

    @inlinable
    init(part: World) {
        self.part = part
    }

    /// Sends `event`, which readers see from the next time they read.
    @inlinable
    public func send(_ event: E) {
        part.send(event)
    }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        .sends(E.self)
    }

    /// Takes the events of type `E` out of `world` until ``_restore(into:)``.
    @inlinable
    public static func _fetch(from world: inout World) -> EventWriter {
        if !world.resources.contains(Events<E>.self) {
            world.resources.insert(Events<E>())
        }
        return EventWriter(part: world.split(writing: _access(in: Self.self)))
    }

    /// Puts the events back into `world`.
    @inlinable
    public func _restore(into world: inout World) {
        world.merge(writing: Self._access(in: Self.self), from: part)
    }
}

// MARK: Commands

extension Commands: SystemParameter {
    /// Commands read and write nothing while the system runs: they apply after it.
    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        Access()
    }
}
