/// A set of conditions an entity must meet, beyond holding the components a query reads.
///
/// A filter can require component types, exclude them, require components added or changed since
/// a tick, and require a relation to a target. Filters read nothing: an entity's components decide
/// whether it passes, but a query's rows carry only the values of its terms.
///
/// Build a filter from a static method such as ``with(_:)-swift.type.method`` and refine it with
/// the instance methods of the same names. Each method returns a new filter that an entity passes
/// only if it meets every condition. To pass entities that meet at least one of several filters,
/// use ``anyOf(_:)-swift.type.method``, so you can write any condition on which component types an
/// entity holds:
///
/// ```swift
/// var world = World()
/// world.spawn(Name(value: "drifter"), Velocity(dx: 1, dy: 0))
/// world.spawn(Name(value: "statue"), Frozen())
/// world.spawn(Name(value: "ghost"), Velocity(dx: 1, dy: 0), Frozen())
/// world.spawn(Name(value: "rock"))
///
/// let moving = QueryFilter.with(Velocity.self).without(Frozen.self)
/// let movingOrFrozen = QueryFilter.anyOf(.with(Velocity.self), .with(Frozen.self))
///
/// let movingNames = world.query(Name.self).filtered(by: moving).map { $0.1.value }
/// print(movingNames)
/// // Prints "["drifter"]"
///
/// let movingOrFrozenNames = world.query(Name.self).filtered(by: movingOrFrozen).map { $0.1.value }
/// print(movingOrFrozenNames)
/// // Prints "["drifter", "statue", "ghost"]"
/// ```
///
/// Pass a filter to ``Query/init(filter:)``, to ``Query/filtered(by:)``, or as the `where`
/// argument of `update(_:reading:where:body:)`. Queries, views and updates also offer the same
/// methods directly, so you can write `Query(Name.self).without(Frozen.self)`.
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
    /// Pairs an entity must be the source of: a relation's ``Targets`` type and a target.
    @usableFromInline var related: [RelatedTarget] = []

    /// A relation, by its ``Targets`` type, and a target an entity must relate to by it.
    @frozen
    @usableFromInline
    struct RelatedTarget: Hashable, Sendable {
        @usableFromInline let type: ObjectIdentifier
        @usableFromInline let target: Entity

        @inlinable
        init(type: ObjectIdentifier, target: Entity) {
            self.type = type
            self.target = target
        }
    }

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

    /// Creates a filter that every entity passes.
    @inlinable
    public init() {}

    /// Returns a filter that passes the entities holding every one of the given component types.
    ///
    /// - Parameter types: The component types an entity must hold.
    /// - Returns: A filter with that one condition.
    @inlinable
    public static func with<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        QueryFilter().with(repeat each types)
    }

    /// Returns a filter that passes the entities holding none of the given component types.
    ///
    /// - Parameter types: The component types an entity must not hold.
    /// - Returns: A filter with that one condition.
    @inlinable
    public static func without<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        QueryFilter().without(repeat each types)
    }

    /// Returns a filter that passes the entities related to the given target.
    ///
    /// A visit with this filter walks only the target's sources, not every entity holding the
    /// queried types. To pass the entities related by `R` to any target, require the relation's
    /// ``Targets`` component instead: `.with(Targets<R>.self)`.
    ///
    /// - Parameters:
    ///   - type: The relation type.
    ///   - target: The entity a passing entity must relate to by `type`.
    /// - Returns: A filter with that one condition.
    @inlinable
    public static func related<R: Relation>(_ type: R.Type, to target: Entity) -> QueryFilter {
        QueryFilter().related(R.self, to: target)
    }

    /// Returns a filter that passes the entities whose component of the given type was added after
    /// a tick.
    ///
    /// - Parameters:
    ///   - type: The component type an entity must have gained.
    ///   - since: The tick the component must be newer than. Pass `nil`, the default, to compare
    ///     against the world's ``World/lastRun``, which a schedule sets to the running system's
    ///     previous run.
    /// - Returns: A filter with that one condition.
    @inlinable
    public static func added<C: Component>(_ type: C.Type, since: ChangeTick? = nil) -> QueryFilter {
        QueryFilter().added(C.self, since: since)
    }

    /// Returns a filter that passes the entities whose component of the given type was added or
    /// changed after a tick.
    ///
    /// Writing a component through the world's subscript, an update or a mutable span marks it
    /// changed at the world's current ``World/changeTick``.
    ///
    /// - Parameters:
    ///   - type: The component type that must have been added or changed.
    ///   - since: The tick the change must be newer than. Pass `nil`, the default, to compare
    ///     against the world's ``World/lastRun``, which a schedule sets to the running system's
    ///     previous run.
    /// - Returns: A filter with that one condition.
    @inlinable
    public static func changed<C: Component>(_ type: C.Type, since: ChangeTick? = nil) -> QueryFilter {
        QueryFilter().changed(C.self, since: since)
    }

    /// Returns a filter that also passes the entities holding the given disabling components.
    ///
    /// A query skips entities that hold a disabling component, such as ``Disabled`` or ``Prefab``,
    /// unless it reads that type or names it in its filter. This filter names the types without
    /// requiring them, so entities pass whether or not they hold them.
    ///
    /// - Parameter types: The disabling component types whose entities pass.
    /// - Returns: A filter with that one condition.
    @inlinable
    public static func allowing<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        QueryFilter().allowing(repeat each types)
    }

    /// Returns a filter that passes the entities that pass at least one of the given filters.
    ///
    /// - Parameter filters: The alternatives. With none, the filter passes no entity.
    /// - Returns: A filter with that one condition.
    @inlinable
    public static func anyOf(_ filters: QueryFilter...) -> QueryFilter {
        QueryFilter().anyOf(filters)
    }

    /// Returns this filter, also requiring that an entity pass at least one of the given filters.
    ///
    /// - Parameter filters: The alternatives. With none, the filter passes no entity.
    /// - Returns: A filter with this filter's conditions and the new one.
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

    /// Returns this filter, also requiring every one of the given component types.
    ///
    /// - Parameter types: The component types an entity must hold.
    /// - Returns: A filter with this filter's conditions and the new one.
    @inlinable
    public func with<each C: Component>(_ types: repeat (each C).Type) -> QueryFilter {
        var filter = self
        for type in repeat each types {
            filter.required.append(ObjectIdentifier(type))
        }
        return filter
    }

    /// Returns this filter, also requiring a relation to the given target.
    ///
    /// - Parameters:
    ///   - type: The relation type.
    ///   - target: The entity a passing entity must relate to by `type`.
    /// - Returns: A filter with this filter's conditions and the new one.
    @inlinable
    public func related<R: Relation>(_ type: R.Type, to target: Entity) -> QueryFilter {
        var filter = self
        filter.related.append(RelatedTarget(type: ObjectIdentifier(Targets<R>.self), target: target))
        return filter
    }

    /// Returns this filter, also requiring a component of the given type added after a tick.
    ///
    /// - Parameters:
    ///   - type: The component type an entity must have gained.
    ///   - since: The tick the component must be newer than, or `nil` for the world's
    ///     ``World/lastRun``.
    /// - Returns: A filter with this filter's conditions and the new one.
    @inlinable
    public func added<C: Component>(_ type: C.Type, since: ChangeTick? = nil) -> QueryFilter {
        var filter = self
        filter.addedSince.append(TickCondition(type: ObjectIdentifier(C.self), since: since))
        return filter
    }

    /// Returns this filter, also requiring a component of the given type added or changed after a
    /// tick.
    ///
    /// - Parameters:
    ///   - type: The component type that must have been added or changed.
    ///   - since: The tick the change must be newer than, or `nil` for the world's
    ///     ``World/lastRun``.
    /// - Returns: A filter with this filter's conditions and the new one.
    @inlinable
    public func changed<C: Component>(_ type: C.Type, since: ChangeTick? = nil) -> QueryFilter {
        var filter = self
        filter.changedSince.append(TickCondition(type: ObjectIdentifier(C.self), since: since))
        return filter
    }

    /// Returns this filter, also passing the entities holding the given disabling components.
    ///
    /// The following example counts every named entity, including a disabled one:
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Name(value: "guard"))
    /// world.spawn(Name(value: "sleeper"), Disabled())
    ///
    /// print(world.query(Name.self).count)
    /// // Prints "1"
    /// print(world.query(Name.self).filtered(by: QueryFilter().allowing(Disabled.self)).count)
    /// // Prints "2"
    /// ```
    ///
    /// - Parameter types: The disabling component types whose entities pass.
    /// - Returns: A filter with this filter's conditions and the new one.
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

    /// Returns a filter with the conditions of this filter and another.
    ///
    /// - Parameter other: The filter whose conditions to add.
    /// - Returns: A filter that an entity passes only if it passes both.
    @inlinable
    public func merging(_ other: QueryFilter) -> QueryFilter {
        var filter = self
        filter.required += other.required
        filter.excluded += other.excluded
        filter.addedSince += other.addedSince
        filter.changedSince += other.changedSince
        filter.alternatives += other.alternatives
        filter.allowed += other.allowed
        filter.related += other.related
        return filter
    }

    /// Returns this filter, also excluding the entities holding any of the given component types.
    ///
    /// - Parameter types: The component types an entity must not hold.
    /// - Returns: A filter with this filter's conditions and the new one.
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
    /// The entities of a cached query listing every entity the filter passes, or nil.
    @usableFromInline var cached: SparseIndex?
    /// The sources of each pair the filter requires, as lists to walk and sets to check.
    @usableFromInline let relatedSources: [[Entity]]
    @usableFromInline let relatedMembers: [Set<Entity>]
    /// For each tick-checked type whose changes the world tracks, the entities its change log
    /// records after the tick: every entity the condition can pass, without walking the column.
    @usableFromInline let changedEntities: [[Entity]]

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
    /// the filter does not mention and the visit does not read or write (`touching`), for a visit
    /// whose matched entities all hold `terms`.
    @inlinable
    init(_ filter: QueryFilter, in world: World, touching: [ObjectIdentifier], terms: [ObjectIdentifier]) {
        var defaults = filter
        var skipped: [ObjectIdentifier] = []
        for type in world.disablingComponents where !touching.contains(type) && !filter.mentions(type) {
            skipped.append(type)
            if let slot = world.columnPositions.position(of: type), !world.columns[slot].index.dense.isEmpty {
                defaults.excluded.append(type)
            }
        }
        self.init(defaults, in: world)
        if !world.caches.isEmpty {
            cached = world.cachedEntities(
                required: terms + filter.required, excluded: filter.excluded + skipped, alternatives: filter.alternatives)
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
        relatedSources = filter.related.map { pair in
            world.relationIndexes.first { $0.key == pair.type }?.sources(of: pair.target) ?? []
        }
        relatedMembers = relatedSources.map(Set.init)
        // An entity added after a tick also changed after it, so the log serves both conditions.
        changedEntities = (filter.addedSince + filter.changedSince).compactMap { condition in
            guard let slot = world.columnPositions.position(of: condition.type),
                  let log = world.columns[slot].changeLog else { return nil }
            return log.entities(changedAfter: condition.since ?? world.lastRun)
        }
        alternatives = filter.alternatives.map { group in
            group.map { ResolvedFilter($0, in: world) }.filter { !$0.isUnsatisfiable }
        }
        self.isUnsatisfiable = isUnsatisfiable || alternatives.contains(where: \.isEmpty)
    }

    /// The entity lists an entity must be in to pass: candidates for the list a visit walks.
    @inlinable
    var candidates: [[Entity]] {
        var candidates = (required + addedSince.map(\.index) + changedSince.map(\.index)).map(\.dense) + relatedSources
            + changedEntities
        if let cached {
            candidates.append(cached.dense)
        }
        return candidates
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
        for members in relatedMembers where !members.contains(entity) { return false }
        for group in alternatives where !group.contains(where: { $0.passes(entity) }) { return false }
        return true
    }

    /// Whether the filter passes every entity, so checking it can be skipped.
    @inlinable
    var isEmpty: Bool {
        required.isEmpty && excluded.isEmpty && addedSince.isEmpty && changedSince.isEmpty && alternatives.isEmpty
            && relatedMembers.isEmpty
    }
}
