/// Component types an entity must hold, types it must not, and types that must have been added or
/// changed since a tick, beyond the ones a query reads.
///
/// Filters compose: each modifier returns a new filter, which an entity passes only if it meets
/// every condition. ``anyOf(_:)-swift.type.method`` passes entities meeting at least one of several
/// filters, so any condition on which components an entity holds can be written.
///
/// ```swift
/// let living = QueryFilter.with(Player.self).without(Dead.self)
/// let moved = QueryFilter.changed(Position.self)
/// let armedOrShielded = QueryFilter.anyOf(.with(Sword.self, Arm.self), .with(Shield.self))
/// ```
@frozen
public struct QueryFilter: Hashable, Sendable {
    @usableFromInline var required: [ObjectIdentifier] = []
    @usableFromInline var excluded: [ObjectIdentifier] = []
    @usableFromInline var addedSince: [TickCondition] = []
    @usableFromInline var changedSince: [TickCondition] = []
    /// Groups of filters, each passed when at least one of its filters passes.
    @usableFromInline var alternatives: [[QueryFilter]] = []
    /// Disabling component types whose entities the filter does not skip.
    @usableFromInline var allowed: [ObjectIdentifier] = []

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

    /// A filter that passes entities holding any of `types`, disabling components that queries
    /// skip by default (``World/registerDisablingComponent(_:)``), as well as those that do not.
    @inlinable
    public static func allowing<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        QueryFilter().allowing(repeat each types)
    }

    /// A filter that passes entities that at least one of `filters` passes.
    ///
    /// With no filters, it passes nothing.
    @inlinable
    public static func anyOf(_ filters: QueryFilter...) -> QueryFilter {
        QueryFilter().anyOf(filters)
    }

    /// This filter, also requiring that at least one of `filters` passes.
    ///
    /// With no filters, it passes nothing.
    @inlinable
    public func anyOf(_ filters: QueryFilter...) -> QueryFilter {
        anyOf(filters)
    }

    /// This filter, also requiring that at least one of `filters` passes.
    @inlinable
    func anyOf(_ filters: [QueryFilter]) -> QueryFilter {
        var filter = self
        filter.alternatives.append(filters)
        return filter
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

    /// This filter, also passing entities holding any of `types`, disabling components that
    /// queries skip by default (``World/registerDisablingComponent(_:)``).
    ///
    /// ```swift
    /// for (entity, name) in world.query(Name.self).allowing(Disabled.self) { … }
    /// ```
    @inlinable
    public func allowing<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        var filter = self
        for type in repeat each types {
            filter.allowed.append(ObjectIdentifier(type))
        }
        return filter
    }

    /// Whether the filter names `type` in any condition, so a query with it does not skip
    /// entities holding `type` by default.
    @inlinable
    func mentions(_ type: ObjectIdentifier) -> Bool {
        required.contains(type) || excluded.contains(type) || allowed.contains(type)
            || addedSince.contains { $0.type == type } || changedSince.contains { $0.type == type }
            || alternatives.contains { group in group.contains { $0.mentions(type) } }
    }

    /// This filter, also requiring everything `other` requires.
    @inlinable
    public func merging(_ other: QueryFilter) -> QueryFilter {
        var filter = self
        filter.required += other.required
        filter.excluded += other.excluded
        filter.addedSince += other.addedSince
        filter.changedSince += other.changedSince
        filter.alternatives += other.alternatives
        filter.allowed += other.allowed
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
    /// Groups of filters, each passed when at least one of its satisfiable filters passes.
    @usableFromInline let alternatives: [[ResolvedFilter]]
    /// Whether some required or tick-checked type has no column, or some group of alternatives
    /// has no filter that can pass, so nothing passes.
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

    /// `filter` resolved against `world`, also skipping the entities holding a disabling component
    /// the filter does not mention and the visit does not read or write (`touching`).
    @inlinable
    init(_ filter: QueryFilter, in world: World, touching: [ObjectIdentifier]) {
        var defaults = filter
        for type in world.disablingComponents where !touching.contains(type) && !filter.mentions(type) {
            if let slot = world.columnPositions.position(of: type), !world.columns[slot].index.dense.isEmpty {
                defaults.excluded.append(type)
            }
        }
        self.init(defaults, in: world)
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
        alternatives = filter.alternatives.map { group in
            group.map { ResolvedFilter($0, in: world) }.filter { !$0.isUnsatisfiable }
        }
        self.isUnsatisfiable = isUnsatisfiable || alternatives.contains(where: \.isEmpty)
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
        for group in alternatives where !group.contains(where: { $0.passes(entity) }) { return false }
        return true
    }

    /// Whether the filter passes every entity, so checking it can be skipped.
    @inlinable
    var isEmpty: Bool {
        required.isEmpty && excluded.isEmpty && addedSince.isEmpty && changedSince.isEmpty && alternatives.isEmpty
    }
}
