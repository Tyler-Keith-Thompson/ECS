/// Component types an entity must hold, types it must not, and types that must have been added or
/// changed since a tick, beyond the ones a query reads.
///
/// Filters compose: each modifier returns a new filter.
///
/// ```swift
/// let living = QueryFilter.with(Player.self).without(Dead.self)
/// let moved = QueryFilter.changed(Position.self)
/// ```
@frozen
public struct QueryFilter: Hashable, Sendable {
    @usableFromInline var required: [ObjectIdentifier] = []
    @usableFromInline var excluded: [ObjectIdentifier] = []
    @usableFromInline var addedSince: [TickCondition] = []
    @usableFromInline var changedSince: [TickCondition] = []

    /// A type whose component must carry a tick after `since`, or after the world's
    /// ``World/lastRun`` when `since` is nil.
    @frozen
    @usableFromInline
    struct TickCondition: Hashable, Sendable {
        @usableFromInline let type: ObjectIdentifier
        @usableFromInline let since: ChangeTick?

        @inlinable
        init(type: ObjectIdentifier, since: ChangeTick?) {
            self.type = type
            self.since = since
        }
    }

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

    /// A filter that passes entities whose `C` was added after `since`.
    ///
    /// - Parameter since: The tick to compare against; nil for the world's ``World/lastRun``,
    ///   which a schedule sets to the running system's previous run.
    @inlinable
    public static func added<C: Component>(_ type: C.Type, since: ChangeTick? = nil) -> QueryFilter {
        QueryFilter().added(C.self, since: since)
    }

    /// A filter that passes entities whose `C` was added or changed after `since`.
    ///
    /// - Parameter since: The tick to compare against; nil for the world's ``World/lastRun``,
    ///   which a schedule sets to the running system's previous run.
    @inlinable
    public static func changed<C: Component>(_ type: C.Type, since: ChangeTick? = nil) -> QueryFilter {
        QueryFilter().changed(C.self, since: since)
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

    /// This filter, also requiring that the `C` was added after `since` (nil for the world's
    /// ``World/lastRun``).
    @inlinable
    public func added<C: Component>(_ type: C.Type, since: ChangeTick? = nil) -> QueryFilter {
        var filter = self
        filter.addedSince.append(TickCondition(type: ObjectIdentifier(C.self), since: since))
        return filter
    }

    /// This filter, also requiring that the `C` was added or changed after `since` (nil for the
    /// world's ``World/lastRun``).
    @inlinable
    public func changed<C: Component>(_ type: C.Type, since: ChangeTick? = nil) -> QueryFilter {
        var filter = self
        filter.changedSince.append(TickCondition(type: ObjectIdentifier(C.self), since: since))
        return filter
    }

    /// This filter, also requiring everything `other` requires.
    @inlinable
    public func merging(_ other: QueryFilter) -> QueryFilter {
        var filter = self
        filter.required += other.required
        filter.excluded += other.excluded
        filter.addedSince += other.addedSince
        filter.changedSince += other.changedSince
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

/// A filter resolved against one world: the indexes of its required, excluded and tick-checked
/// columns.
@frozen
@usableFromInline
struct ResolvedFilter: Sendable {
    @usableFromInline let required: [SparseIndex]
    @usableFromInline let excluded: [SparseIndex]
    @usableFromInline let addedSince: [ResolvedTickCondition]
    @usableFromInline let changedSince: [ResolvedTickCondition]
    /// Whether some required or tick-checked type has no column, so nothing passes.
    @usableFromInline let isUnsatisfiable: Bool

    /// A tick-checked column and the tick its components must be newer than.
    @frozen
    @usableFromInline
    struct ResolvedTickCondition: Sendable {
        @usableFromInline let index: SparseIndex
        @usableFromInline let since: ChangeTick

        @inlinable
        init(index: SparseIndex, since: ChangeTick) {
            self.index = index
            self.since = since
        }
    }

    @inlinable
    init(_ filter: QueryFilter, in world: World) {
        var isUnsatisfiable = false
        func index(_ type: ObjectIdentifier) -> SparseIndex? {
            guard let slot = world.columnPositions.position(of: type) else {
                isUnsatisfiable = true
                return nil
            }
            return world.columns[slot].index
        }
        required = filter.required.compactMap(index)
        addedSince = filter.addedSince.compactMap { condition in
            index(condition.type).map { ResolvedTickCondition(index: $0, since: condition.since ?? world.lastRun) }
        }
        changedSince = filter.changedSince.compactMap { condition in
            index(condition.type).map { ResolvedTickCondition(index: $0, since: condition.since ?? world.lastRun) }
        }
        excluded = filter.excluded.compactMap { type in world.columnPositions.position(of: type).map { world.columns[$0].index } }
        self.isUnsatisfiable = isUnsatisfiable
    }

    /// The columns an entity must be in to pass: candidates for the column a visit walks.
    @inlinable
    var candidates: [SparseIndex] {
        required + addedSince.map(\.index) + changedSince.map(\.index)
    }

    /// Whether `entity` holds every required type, no excluded one, and components new enough.
    @inlinable
    func passes(_ entity: Entity) -> Bool {
        for index in required where index.position(of: entity) == nil { return false }
        for index in excluded where index.position(of: entity) != nil { return false }
        for condition in addedSince {
            guard let position = condition.index.position(of: entity),
                  condition.index.ticks[position].added > condition.since else { return false }
        }
        for condition in changedSince {
            guard let position = condition.index.position(of: entity),
                  condition.index.ticks[position].changed > condition.since else { return false }
        }
        return true
    }

    /// Whether the filter passes every entity, so checking it can be skipped.
    @inlinable
    var isEmpty: Bool { required.isEmpty && excluded.isEmpty && addedSince.isEmpty && changedSince.isEmpty }
}
