/// Which entities to visit and what to read of each, independent of any world.
///
/// A query lists its terms, components and ``AnyOf`` groups, and narrows them with filters. An
/// entity matches when it matches every term and passes the filter. Queries are values: keep one
/// in a system, compare it, pass it around, and run it against any world.
///
/// ```swift
/// let movers = Query(Position.self, Velocity.self, AnyOf<Wind, Current>.self)
///     .without(Frozen.self)
///
/// for (entity, position, velocity, (wind, current)) in world.query(movers) {
///     print(entity, position, velocity, wind, current)
/// }
/// world.update(Position.self, over: Query(Velocity.self)) { position, row in
///     position.x += row.components.dx
/// }
/// ```
///
/// As a system parameter, a query arrives bound to the world the system runs on, and iterates its
/// rows directly; see ``Query/Where``.
@frozen
public struct Query<each T: QueryTerm>: Hashable, Sendable {
    /// The conditions entities must meet beyond matching the terms.
    public let filter: QueryFilter
    /// The rows of the world this query is bound to, when it is a system parameter.
    @usableFromInline let view: QueryView<repeat (each T).Value>?

    /// A query of `terms`, passing every entity that matches them all.
    ///
    /// - Complexity: O(1).
    @inlinable
    public init(_ terms: repeat (each T).Type) {
        filter = QueryFilter()
        view = nil
    }

    /// A query of its type's terms, passing the entities that match them all and pass `filter`.
    ///
    /// ```swift
    /// let living = Query<Health>(filter: .without(Dead.self))
    /// ```
    ///
    /// - Complexity: O(1).
    @inlinable
    public init(filter: QueryFilter) {
        self.filter = filter
        view = nil
    }

    @inlinable
    init(filter: QueryFilter, view: QueryView<repeat (each T).Value>?) {
        self.filter = filter
        self.view = view
    }

    /// This query, bound to `view`, the rows ``World/query(_:)`` lists for it: what a system
    /// parameter receives.
    @_documentation(visibility: internal)
    @inlinable
    public func _bound(to view: QueryView<repeat (each T).Value>) -> Query {
        Query(filter: filter, view: view)
    }

    /// Whether two queries have the same terms and filter; a bound world does not count.
    @inlinable
    public static func == (lhs: Query, rhs: Query) -> Bool {
        lhs.filter == rhs.filter
    }

    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(filter)
    }

    /// This query, keeping only entities that also hold every one of `types`.
    @inlinable
    public func with<each F: Component>(_ types: repeat (each F).Type) -> Query {
        Query(filter: filter.with(repeat each types), view: nil)
    }

    /// This query, keeping only entities that hold none of `types`.
    @inlinable
    public func without<each F: Component>(_ types: repeat (each F).Type) -> Query {
        Query(filter: filter.without(repeat each types), view: nil)
    }

    /// This query, also keeping entities holding any of `types`, disabling components it skips
    /// by default (``World/registerDisablingComponent(_:)``).
    @inlinable
    public func allowing<each F: Component>(_ types: repeat (each F).Type) -> Query {
        Query(filter: filter.allowing(repeat each types), view: nil)
    }

    /// This query, keeping only entities whose `F` was added after `since` (nil for the world's
    /// ``World/lastRun``).
    @inlinable
    public func added<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> Query {
        Query(filter: filter.added(F.self, since: since), view: nil)
    }

    /// This query, keeping only entities whose `F` was added or changed after `since` (nil for
    /// the world's ``World/lastRun``).
    @inlinable
    public func changed<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> Query {
        Query(filter: filter.changed(F.self, since: since), view: nil)
    }

    /// This query, keeping only entities that at least one of `filters` passes.
    ///
    /// ```swift
    /// let damaged = Query(Health.self).anyOf(.changed(Health.self), .without(Shield.self))
    /// ```
    @inlinable
    public func anyOf(_ filters: QueryFilter...) -> Query {
        Query(filter: filter.anyOf(filters), view: nil)
    }

    /// This query, keeping only entities that `filter` passes as well.
    @inlinable
    public func filtered(by filter: QueryFilter) -> Query {
        Query(filter: self.filter.merging(filter), view: nil)
    }
}

extension Query: Sequence {
    /// The rows of the world the query is bound to, as a system parameter receives it.
    ///
    /// - Precondition: The query is bound: it is a system parameter. Otherwise iterate
    ///   `world.query(query)`.
    @inlinable
    public func makeIterator() -> QueryView<repeat (each T).Value>.Iterator {
        guard let view else {
            preconditionFailure("A Query iterates only as a system parameter; iterate world.query(query) instead")
        }
        return view.makeIterator()
    }

    /// The query's filter types, as a system parameter spells them:
    /// `Query<Health>.Where<Changed<Health>, Without<Dead>>`.
    ///
    /// A `Where` iterates like the query it holds, which carries the filter the types stand for.
    @frozen
    public struct Where<each F: FilterTerm>: Sequence, Sendable {
        /// The query, with ``filter`` applied.
        public let query: Query

        /// `query`, which carries ``filter``.
        @_documentation(visibility: internal)
        @inlinable
        public init(_bound query: Query) {
            self.query = query
        }

        /// The filter the filter types stand for, every one applied.
        public static var filter: QueryFilter {
            var filter = QueryFilter()
            for type in repeat (each F).self {
                filter = filter.merging(type.filter)
            }
            return filter
        }

        /// The rows of the world the query is bound to.
        ///
        /// - Precondition: The query is bound: it is a system parameter.
        @inlinable
        public func makeIterator() -> QueryView<repeat (each T).Value>.Iterator {
            query.makeIterator()
        }
    }
}

extension World {
    /// The entities matching `query`, with its terms' values, lazily.
    ///
    /// Each row is the entity, labeled `entity`, followed by one value per term: the component
    /// for a component term, a tuple of optionals for an ``AnyOf`` term.
    ///
    /// ```swift
    /// for (entity, position, (wind, current)) in world.query(Query(Position.self, AnyOf<Wind, Current>.self)) {
    ///     print(entity, position, wind, current)
    /// }
    /// ```
    ///
    /// Queries of one, two or three terms, with ``AnyOf`` groups of two to four types, have
    /// overloads specialized for speed.
    ///
    /// - Complexity: O(*t*) to create. Iterating is O(*n*) for *n* entities in the smallest
    ///   component term or required type, or every entity when there is none.
    @inlinable
    public func query<each T: QueryTerm>(_ query: Query<repeat each T>) -> QueryView<repeat (each T).Value> {
        QueryView(world: self, filter: query.filter) { world in
            world.termReader(repeat (each T).self) { entity, values in (entity: entity, repeat each values) }
        }
    }

    /// Changes the `W` of every entity holding one and matching `query`, in place.
    ///
    /// `body` receives the `W` to change and a row of the entity with the query's values. Every
    /// `W` visited is marked changed at the current ``changeTick``.
    ///
    /// ```swift
    /// world.update(Position.self, over: Query(Velocity.self, AnyOf<Wind, Current>.self)) { position, row in
    ///     let (velocity, (wind, current)) = row.components
    ///     position.x += velocity.dx + (wind?.force ?? 0) + (current?.force ?? 0)
    /// }
    /// ```
    ///
    /// Queries of one, two or three terms, with ``AnyOf`` groups of two to four types, have
    /// overloads specialized for speed.
    ///
    /// - Parameters:
    ///   - type: The component type to change.
    ///   - query: The entities to visit and what to read of them.
    ///   - body: Changes one entity's `W`. If it throws, the visit stops; changes already made
    ///     are kept.
    /// - Complexity: O(*n*) for *n* entities in the smallest of `W` and the component terms,
    ///   plus a copy of the `W` storage when another world shares it.
    /// - Precondition: `query` reads no `W`.
    @inlinable
    public mutating func update<W: Component, each T: QueryTerm, Failure: Error>(
        _ type: W.Type,
        over query: Query<repeat each T>,
        body: (inout W, QueryRow<repeat (each T).Value>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(
            W.self, reads: termReads(repeat (each T).self),
            reader: { world in world.termReader(repeat (each T).self) { entity, values in QueryRow(entity: entity, components: (repeat each values)) } },
            filter: query.filter, body: body)
    }

    /// Changes the `A` and `B` of every entity holding both and matching `query`, in place;
    /// see ``update(_:over:body:)``.
    ///
    /// - Precondition: `A` and `B` differ, and `query` reads neither.
    @inlinable
    public mutating func update<A: Component, B: Component, each T: QueryTerm, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        over query: Query<repeat each T>,
        body: (inout A, inout B, QueryRow<repeat (each T).Value>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(
            A.self, B.self, reads: termReads(repeat (each T).self),
            reader: { world in world.termReader(repeat (each T).self) { entity, values in QueryRow(entity: entity, components: (repeat each values)) } },
            filter: query.filter, body: body)
    }

    /// Changes the `A`, `B` and `C` of every entity holding all three and matching `query`, in
    /// place; see ``update(_:over:body:)``.
    ///
    /// - Precondition: `A`, `B` and `C` differ, and `query` reads none of them.
    @inlinable
    public mutating func update<A: Component, B: Component, C: Component, each T: QueryTerm, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        _ third: C.Type,
        over query: Query<repeat each T>,
        body: (inout A, inout B, inout C, QueryRow<repeat (each T).Value>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(
            A.self, B.self, C.self, reads: termReads(repeat (each T).self),
            reader: { world in world.termReader(repeat (each T).self) { entity, values in QueryRow(entity: entity, components: (repeat each values)) } },
            filter: query.filter, body: body)
    }
}
