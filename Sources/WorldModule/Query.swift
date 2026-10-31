/// A description of the entities to visit and the components to read from each.
///
/// A query has *terms* and a *filter*. Each term is either a component type, which an entity must
/// hold and whose value the query reads, or an ``AnyOf`` group, which an entity matches by holding
/// at least one of its types. The filter adds conditions that read nothing: types an entity must
/// or must not hold, components added or changed since a tick, and relations. An entity matches
/// the query when it matches every term and passes the filter.
///
/// A query doesn't belong to any world. Build it once, store it, compare it with another, and run
/// it against any world. The following example finds the entities that move and aren't frozen:
///
/// ```swift
/// var world = World()
/// world.spawn(Name(value: "comet"), Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
/// world.spawn(Name(value: "statue"), Position(x: 4, y: 2), Velocity(dx: 1, dy: 0), Frozen())
/// world.spawn(Name(value: "moon"), Position(x: 9, y: 9))
///
/// let movers = Query(Name.self, Position.self, Velocity.self).without(Frozen.self)
///
/// var names: [String] = []
/// for (_, name, _, _) in world.query(movers) {
///     names.append(name.value)
/// }
/// print(names)
/// // Prints "["comet"]"
/// ```
///
/// Each row starts with the entity, labeled `entity`, followed by one value per term in the order
/// the query lists them. The statue holds every term but is frozen, and the moon has no velocity.
///
/// To change components while you visit them, pass a query to `update(_:over:body:)`. The
/// following example moves every entity that has a velocity and isn't frozen:
///
/// ```swift
/// var world = World()
/// let comet = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
/// let statue = world.spawn(Position(x: 4, y: 2), Velocity(dx: 1, dy: 0), Frozen())
///
/// world.update(Position.self, over: Query(Velocity.self).without(Frozen.self)) { position, row in
///     position.x += row.components.dx
///     position.y += row.components.dy
/// }
/// print(world[Position.self, of: comet])
/// // Prints "Position(x: 1.0, y: 2.0)"
/// print(world[Position.self, of: statue])
/// // Prints "Position(x: 4.0, y: 2.0)"
/// ```
///
/// As a parameter of a system, a query arrives bound to the world the system runs on, and you
/// iterate it directly. A system spells its filter as types; see ``Query/Where``.
///
/// Queries of one to three terms, each a component or an ``AnyOf`` group of two to four types, run
/// through code specialized for their exact shape. Other shapes take a general path that does more
/// work per entity.
@frozen
public struct Query<each T: QueryTerm>: Hashable, Sendable {
    /// The conditions an entity must meet beyond matching the terms.
    public let filter: QueryFilter
    /// The rows of the world this query is bound to, when it is a system parameter.
    @usableFromInline let view: QueryView<repeat (each T).Value>?

    /// Creates a query of the given terms, with no filter.
    ///
    /// ```swift
    /// let movers = Query(Position.self, Velocity.self)
    ///
    /// var world = World()
    /// world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    /// world.spawn(Position(x: 3, y: 3))
    /// print(world.query(movers).count)
    /// // Prints "1"
    /// ```
    ///
    /// - Parameter terms: The component types and ``AnyOf`` groups an entity must match, in the
    ///   order the query's rows list their values.
    /// - Complexity: O(1).
    @inlinable
    public init(_ terms: repeat (each T).Type) {
        filter = QueryFilter()
        view = nil
    }

    /// Creates a query of the terms in its type, applying the given filter.
    ///
    /// Use this initializer when the query's type already names its terms, such as when you
    /// declare a stored property:
    ///
    /// ```swift
    /// let thawed = Query<Position>(filter: .without(Frozen.self))
    ///
    /// var world = World()
    /// world.spawn(Position(x: 1, y: 1))
    /// world.spawn(Position(x: 2, y: 2), Frozen())
    /// print(world.query(thawed).count)
    /// // Prints "1"
    /// ```
    ///
    /// - Parameter filter: The conditions an entity must meet beyond matching the terms.
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

    /// Returns a Boolean value indicating whether two queries have the same filter.
    ///
    /// Two queries of the same type have the same terms, so they're equal when their filters are.
    /// The world a system parameter's query is bound to doesn't take part in the comparison.
    ///
    /// - Parameters:
    ///   - lhs: A query to compare.
    ///   - rhs: Another query of the same terms.
    @inlinable
    public static func == (lhs: Query, rhs: Query) -> Bool {
        lhs.filter == rhs.filter
    }

    /// Hashes the query's filter by feeding it into the given hasher.
    ///
    /// - Parameter hasher: The hasher to use when combining the components of this query.
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(filter)
    }

    /// Returns a query that also requires every one of the given component types.
    ///
    /// The query requires the types without reading them, so its rows don't carry their values.
    ///
    /// - Parameter types: The component types an entity must hold.
    /// - Returns: A query with the same terms and a narrower filter.
    /// - Complexity: O(*t*) for *t* conditions in the filter.
    @inlinable
    public func with<each F: Component>(_ types: repeat (each F).Type) -> Query {
        Query(filter: filter.with(repeat each types), view: nil)
    }

    /// Returns a query that also excludes entities holding any of the given component types.
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Position(x: 0, y: 0))
    /// world.spawn(Position(x: 1, y: 1), Frozen())
    ///
    /// let thawed = Query(Position.self).without(Frozen.self)
    /// print(world.query(thawed).count)
    /// // Prints "1"
    /// ```
    ///
    /// - Parameter types: The component types an entity must not hold.
    /// - Returns: A query with the same terms and a narrower filter.
    /// - Complexity: O(*t*) for *t* conditions in the filter.
    @inlinable
    public func without<each F: Component>(_ types: repeat (each F).Type) -> Query {
        Query(filter: filter.without(repeat each types), view: nil)
    }

    /// Returns a query that also visits entities holding the given disabling components.
    ///
    /// A query skips entities that hold a disabling component, such as ``Disabled`` or ``Prefab``,
    /// unless it reads that type or names it in its filter. Use this method to include those
    /// entities without requiring the type. To make a type of your own disabling, call
    /// ``World/registerDisablingComponent(_:)``.
    ///
    /// - Parameter types: The disabling component types whose entities the query visits.
    /// - Returns: A query with the same terms and a wider filter.
    /// - Complexity: O(*t*) for *t* conditions in the filter.
    @inlinable
    public func allowing<each F: Component>(_ types: repeat (each F).Type) -> Query {
        Query(filter: filter.allowing(repeat each types), view: nil)
    }

    /// Returns a query that also requires a relation to the given target.
    ///
    /// The query visits only the target's sources, so it doesn't walk every entity holding its
    /// terms.
    ///
    /// - Parameters:
    ///   - type: The relation type.
    ///   - target: The entity a matching entity must relate to by `type`.
    /// - Returns: A query with the same terms and a narrower filter.
    /// - Complexity: O(*t*) for *t* conditions in the filter.
    @inlinable
    public func related<R: Relation>(_ type: R.Type, to target: Entity) -> Query {
        Query(filter: filter.related(R.self, to: target), view: nil)
    }

    /// Returns a query that also requires a component added after the given tick.
    ///
    /// - Parameters:
    ///   - type: The component type an entity must have gained.
    ///   - since: The tick the component must be newer than. Pass `nil`, the default, to compare
    ///     against the world's ``World/lastRun``, so that a system sees the components added since
    ///     its previous run.
    /// - Returns: A query with the same terms and a narrower filter.
    /// - Complexity: O(*t*) for *t* conditions in the filter.
    @inlinable
    public func added<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> Query {
        Query(filter: filter.added(F.self, since: since), view: nil)
    }

    /// Returns a query that also requires a component added or changed after the given tick.
    ///
    /// The following example finds the entities whose health changed after a checkpoint:
    ///
    /// ```swift
    /// var world = World()
    /// let hero = world.spawn(Health(current: 10))
    /// world.spawn(Health(current: 8))
    ///
    /// let checkpoint = world.changeTick
    /// world.advanceChangeTick()
    /// world[Health.self, of: hero].current -= 1
    ///
    /// let hurt = Query(Health.self).changed(Health.self, since: checkpoint)
    /// print(world.query(hurt).count)
    /// // Prints "1"
    /// ```
    ///
    /// - Parameters:
    ///   - type: The component type that must have been added or changed.
    ///   - since: The tick the change must be newer than. Pass `nil`, the default, to compare
    ///     against the world's ``World/lastRun``, so that a system sees the changes made since its
    ///     previous run.
    /// - Returns: A query with the same terms and a narrower filter.
    /// - Complexity: O(*t*) for *t* conditions in the filter.
    @inlinable
    public func changed<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> Query {
        Query(filter: filter.changed(F.self, since: since), view: nil)
    }

    /// Returns a query that also requires an entity to pass at least one of the given filters.
    ///
    /// The following example finds the entities that are frozen or have no velocity:
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    /// world.spawn(Position(x: 1, y: 1), Velocity(dx: 1, dy: 0), Frozen())
    /// world.spawn(Position(x: 2, y: 2))
    ///
    /// let still = Query(Position.self).anyOf(.with(Frozen.self), .without(Velocity.self))
    /// print(world.query(still).count)
    /// // Prints "2"
    /// ```
    ///
    /// - Parameter filters: The alternatives. With none, the query matches no entity.
    /// - Returns: A query with the same terms and a narrower filter.
    /// - Complexity: O(*t*) for *t* conditions in the filter.
    @inlinable
    public func anyOf(_ filters: QueryFilter...) -> Query {
        Query(filter: filter.anyOf(filters), view: nil)
    }

    /// Returns a query that also requires every condition of the given filter.
    ///
    /// - Parameter filter: The conditions to add.
    /// - Returns: A query with the same terms and a filter combining both.
    /// - Complexity: O(*t*) for *t* conditions in the two filters.
    @inlinable
    public func filtered(by filter: QueryFilter) -> Query {
        Query(filter: self.filter.merging(filter), view: nil)
    }
}

extension Query: Sequence {
    /// Returns an iterator over the rows of the world the query is bound to.
    ///
    /// A query is bound to a world only when a system receives it as a parameter. To iterate a
    /// query you built yourself, pass it to a world's `query(_:)` method instead.
    ///
    /// - Important: Iterating a query that isn't bound to a world traps.
    @inlinable
    public func makeIterator() -> QueryView<repeat (each T).Value>.Iterator {
        guard let view else {
            preconditionFailure("A Query iterates only as a system parameter; iterate world.query(query) instead")
        }
        return view.makeIterator()
    }

    /// A query whose filter a system spells as types.
    ///
    /// A system declares what it reads through the types of its parameters, so it can't pass a
    /// ``QueryFilter`` value. Instead, it names the filter with filter types, such as ``With``,
    /// ``Without``, ``Added`` and ``Changed``. A system that counts the entities with a position
    /// that aren't frozen declares a parameter of type `Query<Position>.Where<Without<Frozen>>`,
    /// and iterates it like the query it holds, with `for (entity, position) in positions`.
    ///
    /// Listing several filter types passes the entities that pass all of them. Each filter type
    /// stands for a ``QueryFilter``, and the `Where` type's ``filter`` combines them:
    ///
    /// ```swift
    /// let filter = Query<Health>.Where<Changed<Health>, Without<Frozen>>.filter
    /// print(filter == QueryFilter.changed(Health.self).without(Frozen.self))
    /// // Prints "true"
    /// ```
    ///
    /// Use ``AnyOf`` of filter types to pass the entities that pass at least one of them.
    @frozen
    public struct Where<each F: FilterTerm>: Sequence, Sendable {
        /// The query, carrying the filter that the filter types stand for.
        public let query: Query

        /// `query`, which carries ``filter``.
        @_documentation(visibility: internal)
        @inlinable
        public init(_bound query: Query) {
            self.query = query
        }

        /// The filter that the filter types stand for, with every one of them applied.
        public static var filter: QueryFilter {
            var filter = QueryFilter()
            for type in repeat (each F).self {
                filter = filter.merging(type.filter)
            }
            return filter
        }

        /// Returns an iterator over the rows of the world the query is bound to.
        ///
        /// - Important: Iterating a `Where` whose query isn't bound to a world, because no system
        ///   received it as a parameter, traps.
        @inlinable
        public func makeIterator() -> QueryView<repeat (each T).Value>.Iterator {
            query.makeIterator()
        }
    }
}

extension World {
    /// Returns the entities that match a query, with the values of its terms.
    ///
    /// Each row is a tuple of the entity, labeled `entity`, followed by one value per term: the
    /// component for a component term, and a tuple of optionals for an ``AnyOf`` term. The
    /// following example reads the name of every entity pushed by wind, thrust or both, with the
    /// forces it feels:
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Name(value: "kite"), Wind(force: 3))
    /// world.spawn(Name(value: "rocket"), Thrust(force: 5))
    /// world.spawn(Name(value: "rock"))
    ///
    /// var forces: [String] = []
    /// for (_, name, (wind, thrust)) in world.query(Query(Name.self, AnyOf<Wind, Thrust>.self)) {
    ///     forces.append("\(name.value): \((wind?.force ?? 0) + (thrust?.force ?? 0))")
    /// }
    /// print(forces)
    /// // Prints "["kite: 3.0", "rocket: 5.0"]"
    /// ```
    ///
    /// The rock holds neither a wind nor a thrust, so it doesn't match the ``AnyOf`` term.
    ///
    /// The view is lazy: it finds the matching entities as you iterate it.
    ///
    /// - Parameter query: The entities to visit and the components to read.
    /// - Returns: A view of the matching rows, as of this moment.
    /// - Complexity: O(*t*) for *t* terms to create. Iterating is O(*n*) for *n* entities in the
    ///   smallest component term or required type, or every entity when there's none.
    @inlinable
    public func query<each T: QueryTerm>(_ query: Query<repeat each T>) -> QueryView<repeat (each T).Value> {
        QueryView(world: self, filter: query.filter) { world in
            world.termReader(repeat (each T).self) { entity, values in (entity: entity, repeat each values) }
        }
    }

    /// Changes a component of every entity that matches a query, in place.
    ///
    /// The method visits every entity that holds a `W` and matches `query`. For each one, `body`
    /// receives the entity's `W` to change, and a ``QueryRow`` carrying the entity and the values
    /// of the query's terms. Every `W` visited is marked changed at the world's current
    /// ``changeTick``. The following example declares two forces and moves the entities that
    /// feel at least one of them:
    ///
    /// ```swift
    /// struct Wind: Component { var force: Double }
    /// struct Thrust: Component { var force: Double }
    /// ```
    ///
    /// ```swift
    /// var world = World()
    /// let kite = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Wind(force: 3))
    /// let rocket = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Thrust(force: 5))
    /// let cart = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    ///
    /// world.update(Position.self, over: Query(Velocity.self, AnyOf<Wind, Thrust>.self)) { position, row in
    ///     let (velocity, (wind, thrust)) = row.components
    ///     position.x += velocity.dx + (wind?.force ?? 0) + (thrust?.force ?? 0)
    /// }
    /// print(world[Position.self, of: kite])
    /// // Prints "Position(x: 4.0, y: 0.0)"
    /// print(world[Position.self, of: rocket])
    /// // Prints "Position(x: 6.0, y: 0.0)"
    /// print(world[Position.self, of: cart])
    /// // Prints "Position(x: 0.0, y: 0.0)"
    /// ```
    ///
    /// The cart feels neither force, so it doesn't match the ``AnyOf`` term and isn't visited.
    ///
    /// - Parameters:
    ///   - type: The component type to change.
    ///   - query: The entities to visit and the components to read from each.
    ///   - body: A closure that changes one entity's component. If it throws, the visit stops and
    ///     the method rethrows the error; changes already made are kept.
    /// - Complexity: O(*n*) for *n* entities in the smallest of `W` and the component terms, plus
    ///   a copy of the `W` storage when another world shares it.
    /// - Precondition: `query` doesn't read `W`.
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

    /// Changes two components of every entity that matches a query, in place.
    ///
    /// The method visits every entity that holds an `A` and a `B` and matches `query`, and marks
    /// both changed. See `update(_:over:body:)` for how a visit proceeds.
    ///
    /// - Parameters:
    ///   - first: The first component type to change.
    ///   - second: The second component type to change.
    ///   - query: The entities to visit and the components to read from each.
    ///   - body: A closure that changes one entity's components. If it throws, the visit stops
    ///     and the method rethrows the error; changes already made are kept.
    /// - Complexity: O(*n*) for *n* entities in the smallest of `A`, `B` and the component terms.
    /// - Precondition: `A` and `B` are different types, and `query` reads neither.
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

    /// Changes three components of every entity that matches a query, in place.
    ///
    /// The method visits every entity that holds an `A`, a `B` and a `C` and matches `query`, and
    /// marks all three changed. See `update(_:over:body:)` for how a visit proceeds.
    ///
    /// - Parameters:
    ///   - first: The first component type to change.
    ///   - second: The second component type to change.
    ///   - third: The third component type to change.
    ///   - query: The entities to visit and the components to read from each.
    ///   - body: A closure that changes one entity's components. If it throws, the visit stops
    ///     and the method rethrows the error; changes already made are kept.
    /// - Complexity: O(*n*) for *n* entities in the smallest of `A`, `B`, `C` and the component
    ///   terms.
    /// - Precondition: `A`, `B` and `C` are different types, and `query` reads none of them.
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
