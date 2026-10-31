/// An entity an update visits, with the components the update reads from it.
///
/// An update's closure receives the components it writes as `inout` arguments and everything else
/// it reads in a row. The row's ``components`` hold the read values in the order the update lists
/// them. An update that reads one type holds that type's value itself, not a one-element tuple, and
/// an update that reads nothing holds `()`. An ``AnyOf`` term's value is a tuple of optionals.
///
/// ```swift
/// var world = World()
/// let comet = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2), Health(current: 3))
///
/// world.update(Position.self, reading: Velocity.self, Health.self) { position, row in
///     let (velocity, health) = row.components
///     position.x += velocity.dx * Double(health.current)
/// }
/// print(world[Position.self, of: comet])
/// // Prints "Position(x: 3.0, y: 0.0)"
/// ```
@frozen
public struct QueryRow<each C> {
    /// The entity the row describes.
    public let entity: Entity
    /// The values the update reads from the entity, in the order the update lists them.
    public let components: (repeat each C)

    /// Creates a row of the given entity and values.
    ///
    /// - Parameters:
    ///   - entity: The entity the row describes.
    ///   - components: The values read from the entity.
    @inlinable
    public init(entity: Entity, components: (repeat each C)) {
        self.entity = entity
        self.components = components
    }
}

extension QueryRow: Sendable where repeat each C: Sendable {}

/// A lazy sequence of the entities that match a query, with the components the query reads.
///
/// You get a view from a world's `query(_:)` methods. Each row is a tuple of the entity, labeled
/// `entity`, followed by the values of the query's terms in the order the query lists them, so a
/// loop can name them all:
///
/// ```swift
/// var world = World()
/// world.spawn(Name(value: "comet"), Velocity(dx: 3, dy: 4))
/// world.spawn(Name(value: "statue"), Velocity(dx: 1, dy: 1), Frozen())
///
/// for (_, name, velocity) in world.query(Name.self, Velocity.self).without(Frozen.self) {
///     print(name.value, velocity.dx)
///     // Prints "comet 3.0"
/// }
/// ```
///
/// A view is a snapshot of the world it came from: changing the world while you iterate doesn't
/// change what the view shows, though the first write to each component type copies that type's
/// storage. To change components while you visit them, use one of the world's `update` methods
/// instead.
///
/// Narrow a view with the same methods a ``Query`` offers, such as ``with(_:)`` and
/// ``without(_:)``. Each returns a new view.
///
/// Rows come in the order of the list the view walks: the storage of the queried or required type
/// that the fewest entities hold, or a shorter list where one applies, such as a target's sources
/// for ``related(_:to:)`` or a cached query's entities. That order depends only on the steps that
/// built the world, so it's the same every time you run the same steps.
@frozen
public struct QueryView<each C>: Sequence, Sendable {
    @usableFromInline let world: World
    /// The conditions an entity must meet, beyond holding the components the rows carry.
    public let filter: QueryFilter
    @usableFromInline let makeReader: @Sendable (World) -> Reader<(entity: Entity, repeat each C)>

    @inlinable
    init(world: World, filter: QueryFilter, makeReader: @escaping @Sendable (World) -> Reader<(entity: Entity, repeat each C)>) {
        self.world = world
        self.filter = filter
        self.makeReader = makeReader
    }

    /// Returns a view that also requires every one of the given component types.
    ///
    /// - Parameter types: The component types an entity must hold.
    /// - Returns: A view of the entities that also hold every one of `types`.
    @inlinable
    public func with<each F: Component>(_ types: repeat (each F).Type) -> QueryView {
        QueryView(world: world, filter: filter.with(repeat each types), makeReader: makeReader)
    }

    /// Returns a view that also excludes entities holding any of the given component types.
    ///
    /// - Parameter types: The component types an entity must not hold.
    /// - Returns: A view of the entities that also hold none of `types`.
    @inlinable
    public func without<each F: Component>(_ types: repeat (each F).Type) -> QueryView {
        QueryView(world: world, filter: filter.without(repeat each types), makeReader: makeReader)
    }

    /// Returns a view that also includes the entities holding the given disabling components.
    ///
    /// A view skips entities that hold a disabling component, such as ``Disabled``, unless it
    /// names the type. Use this method to include them.
    ///
    /// - Parameter types: The disabling component types whose entities the view includes.
    /// - Returns: A view that also includes entities holding any of `types`.
    @inlinable
    public func allowing<each F: Component>(_ types: repeat (each F).Type) -> QueryView {
        QueryView(world: world, filter: filter.allowing(repeat each types), makeReader: makeReader)
    }

    /// Returns a view that also requires a relation to the given target.
    ///
    /// - Parameters:
    ///   - type: The relation type.
    ///   - target: The entity a matching entity must relate to by `type`.
    /// - Returns: A view of the entities that also relate to `target` by `type`.
    @inlinable
    public func related<R: Relation>(_ type: R.Type, to target: Entity) -> QueryView {
        QueryView(world: world, filter: filter.related(R.self, to: target), makeReader: makeReader)
    }

    /// Returns a view that also requires a component added after the given tick.
    ///
    /// - Parameters:
    ///   - type: The component type an entity must have gained.
    ///   - since: The tick the component must be newer than, or `nil`, the default, for the
    ///     world's ``World/lastRun``.
    /// - Returns: A view of the entities whose `type` was also added after `since`.
    @inlinable
    public func added<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> QueryView {
        QueryView(world: world, filter: filter.added(F.self, since: since), makeReader: makeReader)
    }

    /// Returns a view that also requires a component added or changed after the given tick.
    ///
    /// - Parameters:
    ///   - type: The component type that must have been added or changed.
    ///   - since: The tick the change must be newer than, or `nil`, the default, for the world's
    ///     ``World/lastRun``.
    /// - Returns: A view of the entities whose `type` was also added or changed after `since`.
    @inlinable
    public func changed<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> QueryView {
        QueryView(world: world, filter: filter.changed(F.self, since: since), makeReader: makeReader)
    }

    /// Returns a view that also requires an entity to pass at least one of the given filters.
    ///
    /// - Parameter filters: The alternatives. With none, the view is empty.
    /// - Returns: A view of the entities that also pass at least one of `filters`.
    @inlinable
    public func anyOf(_ filters: QueryFilter...) -> QueryView {
        QueryView(world: world, filter: filter.anyOf(filters), makeReader: makeReader)
    }

    /// Returns a view that also requires every condition of the given filter.
    ///
    /// - Parameter filter: The conditions to add.
    /// - Returns: A view of the entities that also pass `filter`.
    @inlinable
    public func filtered(by filter: QueryFilter) -> QueryView {
        QueryView(world: world, filter: self.filter.merging(filter), makeReader: makeReader)
    }

    /// The number of rows in the view.
    ///
    /// The view counts its rows by visiting them.
    ///
    /// - Complexity: O(*n*) for *n* entities in the smallest queried or required type.
    @inlinable
    public var count: Int {
        var count = 0
        var iterator = makeIterator()
        while iterator.next() != nil { count += 1 }
        return count
    }

    /// An iterator over the rows of a query view.
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline let reader: Reader<(entity: Entity, repeat each C)>
        @usableFromInline let filter: ResolvedFilter
        /// The entities visited, in order.
        @usableFromInline let driver: [Entity]
        /// Which read column `driver` is, -1 for a filter type or the live entities, or
        /// `alignedDriver` for the front of an owning group's columns.
        @usableFromInline let driverColumn: Int
        /// The end of the visited part of `driver`.
        @usableFromInline let end: Int
        @usableFromInline var cursor = 0

        @inlinable
        init(world: World, filter: QueryFilter, reader: Reader<(entity: Entity, repeat each C)>) {
            let resolved = ResolvedFilter(filter, in: world, touching: reader.reads, terms: reader.types)
            var driver: [Entity] = []
            var driverColumn = -1
            var hasDriver = false
            for (column, entities) in reader.columns.enumerated() where !hasDriver || entities.count < driver.count {
                driver = entities
                driverColumn = column
                hasDriver = true
            }
            for candidate in resolved.candidates where !hasDriver || candidate.count < driver.count {
                driver = candidate
                driverColumn = -1
                hasDriver = true
            }
            if resolved.isUnsatisfiable {
                driver = []
            } else if !hasDriver {
                driver = Array(world.entities)
            }
            var end = driver.count
            if !resolved.isUnsatisfiable, let aligned = world.alignedCount(of: reader.types) {
                driver = reader.columns[0]
                driverColumn = alignedDriver
                end = aligned
            }
            self.reader = reader
            self.filter = resolved
            self.driver = driver
            self.driverColumn = driverColumn
            self.end = end
        }

        /// Advances to the next row and returns it, or `nil` if no next row exists.
        @inlinable
        public mutating func next() -> Optional<(entity: Entity, repeat each C)> {
            let checksFilter = !filter.isEmpty
            while cursor < end {
                let position = cursor
                let entity = driver[position]
                cursor += 1
                if checksFilter, !filter.passes(entity) { continue }
                if let row = reader.row(entity, position, driverColumn) { return .some(row) }
            }
            return nil
        }
    }

    /// Returns an iterator over the rows of the view.
    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(world: world, filter: filter, reader: makeReader(world))
    }
}

extension World {
    /// Returns the entities that hold every one of the given component types, with those
    /// components.
    ///
    /// Use this method to read the components of every entity that holds a set of types. Each row
    /// is a tuple of the entity, labeled `entity`, followed by one component per type:
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Name(value: "comet"), Position(x: 1, y: 2), Velocity(dx: 3, dy: 4), Health(current: 5))
    /// world.spawn(Name(value: "rock"), Position(x: 0, y: 0))
    ///
    /// for (_, name, position, velocity, health) in world.query(Name.self, Position.self, Velocity.self, Health.self) {
    ///     print(name.value, position.x + velocity.dx, health.current)
    ///     // Prints "comet 4.0 5"
    /// }
    /// ```
    ///
    /// Narrow the view with methods such as ``QueryView/without(_:)``, or build a ``Query`` to
    /// keep the description and use it with `query(_:)`. Queries of one, two or three types run
    /// through code specialized for that number of types.
    ///
    /// - Parameter types: The component types an entity must hold, in the order rows list them.
    /// - Returns: A view of the matching entities, as of this moment.
    /// - Complexity: O(*t*) for *t* types to create. Iterating is O(*n*) for *n* entities in the
    ///   smallest queried or required type.
    @inlinable
    public func query<each C: Component>(_ types: repeat (each C).Type) -> QueryView<repeat each C> {
        QueryView(world: self, filter: QueryFilter()) { world in
            world.packReader(repeat (each C).self) { entity, components in (entity: entity, repeat each components) }
        }
    }

    /// Returns the entities that hold a component of the given type, with that component.
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Health(current: 3))
    /// world.spawn(Health(current: 4))
    ///
    /// var total = 0
    /// for (_, health) in world.query(Health.self) {
    ///     total += health.current
    /// }
    /// print(total)
    /// // Prints "7"
    /// ```
    ///
    /// - Parameter a: The component type to read.
    /// - Returns: A view of the entities holding an `A`, as of this moment.
    /// - Complexity: O(1) to create. Iterating is O(*n*) for *n* entities in the smallest
    ///   queried or required type.
    @inlinable
    public func query<A: Component>(_ a: A.Type) -> QueryView<A> {
        QueryView(world: self, filter: QueryFilter()) { world in
            world.reader(A.self) { entity, a in (entity: entity, a) }
        }
    }

    /// Returns the entities that hold components of both given types, with those components.
    ///
    /// - Parameters:
    ///   - a: The first component type to read.
    ///   - b: The second component type to read.
    /// - Returns: A view of the entities holding an `A` and a `B`, as of this moment.
    /// - Complexity: O(1) to create. Iterating is O(*n*) for *n* entities in the smallest
    ///   queried or required type.
    @inlinable
    public func query<A: Component, B: Component>(_ a: A.Type, _ b: B.Type) -> QueryView<A, B> {
        QueryView(world: self, filter: QueryFilter()) { world in
            world.reader(A.self, B.self) { entity, a, b in (entity: entity, a, b) }
        }
    }

    /// Returns the entities that hold components of all three given types, with those components.
    ///
    /// - Parameters:
    ///   - a: The first component type to read.
    ///   - b: The second component type to read.
    ///   - c: The third component type to read.
    /// - Returns: A view of the entities holding an `A`, a `B` and a `C`, as of this moment.
    /// - Complexity: O(1) to create. Iterating is O(*n*) for *n* entities in the smallest
    ///   queried or required type.
    @inlinable
    public func query<A: Component, B: Component, C: Component>(_ a: A.Type, _ b: B.Type, _ c: C.Type) -> QueryView<A, B, C> {
        QueryView(world: self, filter: QueryFilter()) { world in
            world.reader(A.self, B.self, C.self) { entity, a, b, c in (entity: entity, a, b, c) }
        }
    }
}

/// A lazy sequence of the entities that pass a filter, without reading any of their components.
///
/// You get a view from a world's `query()` method, which lists every live entity, and narrow it
/// with methods such as ``with(_:)`` and ``without(_:)``. Use it when you need the entities
/// themselves, for example to despawn them or pass them to commands:
///
/// ```swift
/// var world = World()
/// world.spawn(Position(x: 0, y: 0), Frozen())
/// world.spawn(Position(x: 1, y: 1))
/// world.spawn(Frozen())
///
/// for entity in world.query().with(Frozen.self, Position.self) {
///     world.despawn(entity)
/// }
/// print(world.query().count)
/// // Prints "2"
/// ```
///
/// Like ``QueryView``, a view is a snapshot of the world it came from, so the loop above can
/// change the world while it iterates.
@frozen
public struct EntityQueryView: Sequence, Sendable {
    @usableFromInline let world: World
    /// The conditions an entity must meet.
    public let filter: QueryFilter

    @inlinable
    init(world: World, filter: QueryFilter) {
        self.world = world
        self.filter = filter
    }

    /// Returns a view that also requires every one of the given component types.
    ///
    /// - Parameter types: The component types an entity must hold.
    /// - Returns: A view of the entities that also hold every one of `types`.
    @inlinable
    public func with<each F: Component>(_ types: repeat (each F).Type) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.with(repeat each types))
    }

    /// Returns a view that also excludes entities holding any of the given component types.
    ///
    /// - Parameter types: The component types an entity must not hold.
    /// - Returns: A view of the entities that also hold none of `types`.
    @inlinable
    public func without<each F: Component>(_ types: repeat (each F).Type) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.without(repeat each types))
    }

    /// Returns a view that also includes the entities holding the given disabling components.
    ///
    /// A view skips entities that hold a disabling component, such as ``Disabled``, unless it
    /// names the type. Use this method to include them.
    ///
    /// - Parameter types: The disabling component types whose entities the view includes.
    /// - Returns: A view that also includes entities holding any of `types`.
    @inlinable
    public func allowing<each F: Component>(_ types: repeat (each F).Type) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.allowing(repeat each types))
    }

    /// Returns a view that also requires a relation to the given target.
    ///
    /// - Parameters:
    ///   - type: The relation type.
    ///   - target: The entity a matching entity must relate to by `type`.
    /// - Returns: A view of the entities that also relate to `target` by `type`.
    @inlinable
    public func related<R: Relation>(_ type: R.Type, to target: Entity) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.related(R.self, to: target))
    }

    /// Returns a view that also requires a component added after the given tick.
    ///
    /// - Parameters:
    ///   - type: The component type an entity must have gained.
    ///   - since: The tick the component must be newer than, or `nil`, the default, for the
    ///     world's ``World/lastRun``.
    /// - Returns: A view of the entities whose `type` was also added after `since`.
    @inlinable
    public func added<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.added(F.self, since: since))
    }

    /// Returns a view that also requires a component added or changed after the given tick.
    ///
    /// - Parameters:
    ///   - type: The component type that must have been added or changed.
    ///   - since: The tick the change must be newer than, or `nil`, the default, for the world's
    ///     ``World/lastRun``.
    /// - Returns: A view of the entities whose `type` was also added or changed after `since`.
    @inlinable
    public func changed<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.changed(F.self, since: since))
    }

    /// Returns a view that also requires an entity to pass at least one of the given filters.
    ///
    /// - Parameter filters: The alternatives. With none, the view is empty.
    /// - Returns: A view of the entities that also pass at least one of `filters`.
    @inlinable
    public func anyOf(_ filters: QueryFilter...) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.anyOf(filters))
    }

    /// Returns a view that also requires every condition of the given filter.
    ///
    /// - Parameter filter: The conditions to add.
    /// - Returns: A view of the entities that also pass `filter`.
    @inlinable
    public func filtered(by filter: QueryFilter) -> EntityQueryView {
        EntityQueryView(world: world, filter: self.filter.merging(filter))
    }

    /// The number of entities in the view.
    ///
    /// The view counts its entities by visiting them.
    ///
    /// - Complexity: O(*n*) for *n* entities in the smallest required type, or the world's slots
    ///   when no type is required.
    @inlinable
    public var count: Int {
        var count = 0
        var iterator = makeIterator()
        while iterator.next() != nil { count += 1 }
        return count
    }

    /// An iterator over the entities of an entity query view.
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline let filter: ResolvedFilter
        @usableFromInline let driver: [Entity]
        @usableFromInline var cursor = 0

        @inlinable
        init(world: World, filter: QueryFilter) {
            let resolved = ResolvedFilter(filter, in: world, touching: [], terms: [])
            var driver: [Entity]? = nil
            for candidate in resolved.candidates where driver == nil || candidate.count < driver!.count {
                driver = candidate
            }
            self.filter = resolved
            self.driver = resolved.isUnsatisfiable ? [] : driver ?? Array(world.entities)
        }

        /// Advances to the next entity and returns it, or `nil` if no next entity exists.
        @inlinable
        public mutating func next() -> Entity? {
            let checksFilter = !filter.isEmpty
            while cursor < driver.count {
                let entity = driver[cursor]
                cursor += 1
                if !checksFilter || filter.passes(entity) { return entity }
            }
            return nil
        }
    }

    /// Returns an iterator over the entities of the view.
    @inlinable
    public func makeIterator() -> Iterator { Iterator(world: world, filter: filter) }
}

extension World {
    /// Returns every live entity, to narrow with a filter.
    ///
    /// Narrow the view with methods such as ``EntityQueryView/with(_:)`` and
    /// ``EntityQueryView/without(_:)``. Like other queries, it skips entities holding a disabling
    /// component, such as ``Disabled``, unless the filter names the type.
    ///
    /// - Returns: A view of the live entities, as of this moment.
    /// - Complexity: O(1) to create.
    @inlinable
    public func query() -> EntityQueryView {
        EntityQueryView(world: self, filter: QueryFilter())
    }
}
