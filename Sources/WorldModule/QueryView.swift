/// An entity and what an update reads of it, in the order the update listed its terms.
///
/// An update reading one term has that term's value itself as `components`, not a one-element
/// tuple; reading none, `components` is `()`. An ``AnyOf`` term's value is a tuple of optionals.
@frozen
public struct QueryRow<each C> {
    /// The entity.
    public let entity: Entity
    /// Its terms' values, in the order the query listed them.
    public let components: (repeat each C)

    @inlinable
    public init(entity: Entity, components: (repeat each C)) {
        self.entity = entity
        self.components = components
    }
}

extension QueryRow: Sendable where repeat each C: Sendable {}

/// The entities holding every component type of a query and passing its filter, with those
/// components, lazily.
///
/// Each row is a tuple of the entity, labeled `entity`, and its terms' values in the order the
/// query listed them, so a loop can name them all:
///
/// ```swift
/// for (entity, position, velocity) in world.query(Position.self, Velocity.self).without(Frozen.self) {
///     print(entity, position, velocity)
/// }
/// ```
///
/// A view is a snapshot of the world it came from: writing to the world while iterating does not
/// change what the view shows, though the first write to each component type copies that type's
/// storage. To change components while visiting them, use ``World/update(_:reading:where:body:)``.
///
/// Rows come in the storage order of the queried or required type held by the fewest entities,
/// which depends only on the history of insertions and removals.
@frozen
public struct QueryView<each C>: Sequence, Sendable {
    @usableFromInline let world: World
    /// The types the rows must hold and must not hold, beyond the components they carry.
    public let filter: QueryFilter
    @usableFromInline let makeReader: @Sendable (World) -> Reader<(entity: Entity, repeat each C)>

    @inlinable
    init(world: World, filter: QueryFilter, makeReader: @escaping @Sendable (World) -> Reader<(entity: Entity, repeat each C)>) {
        self.world = world
        self.filter = filter
        self.makeReader = makeReader
    }

    /// This view, keeping only entities that also hold every one of `types`.
    @inlinable
    public func with<each F: Component>(_ types: repeat (each F).Type) -> QueryView {
        QueryView(world: world, filter: filter.with(repeat each types), makeReader: makeReader)
    }

    /// This view, keeping only entities that hold none of `types`.
    @inlinable
    public func without<each F: Component>(_ types: repeat (each F).Type) -> QueryView {
        QueryView(world: world, filter: filter.without(repeat each types), makeReader: makeReader)
    }

    /// This view, keeping only entities whose `F` was added after `since` (nil for the world's
    /// ``World/lastRun``).
    @inlinable
    public func added<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> QueryView {
        QueryView(world: world, filter: filter.added(F.self, since: since), makeReader: makeReader)
    }

    /// This view, keeping only entities whose `F` was added or changed after `since` (nil for the
    /// world's ``World/lastRun``).
    @inlinable
    public func changed<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> QueryView {
        QueryView(world: world, filter: filter.changed(F.self, since: since), makeReader: makeReader)
    }

    /// This view, keeping only entities that at least one of `filters` passes.
    @inlinable
    public func anyOf(_ filters: QueryFilter...) -> QueryView {
        QueryView(world: world, filter: filter.anyOf(filters), makeReader: makeReader)
    }

    /// This view, keeping only entities that `filter` passes as well.
    @inlinable
    public func filtered(by filter: QueryFilter) -> QueryView {
        QueryView(world: world, filter: self.filter.merging(filter), makeReader: makeReader)
    }

    /// The number of rows.
    ///
    /// - Complexity: O(*n*) for *n* entities in the smallest queried or required type.
    @inlinable
    public var count: Int {
        var count = 0
        var iterator = makeIterator()
        while iterator.next() != nil { count += 1 }
        return count
    }

    /// Steps through a query's rows.
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
            let resolved = ResolvedFilter(filter, in: world)
            var driver: [Entity] = []
            var driverColumn = -1
            var hasDriver = false
            for (column, entities) in reader.columns.enumerated() where !hasDriver || entities.count < driver.count {
                driver = entities
                driverColumn = column
                hasDriver = true
            }
            for index in resolved.candidates where !hasDriver || index.dense.count < driver.count {
                driver = index.dense
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

    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(world: world, filter: filter, reader: makeReader(world))
    }
}

extension World {
    /// The entities holding every one of `types`, with those components, lazily.
    ///
    /// ```swift
    /// for (entity, position, velocity, health) in world.query(Position.self, Velocity.self, Health.self) {
    ///     print(entity, position, velocity, health)
    /// }
    /// ```
    ///
    /// Queries of one, two or three types have overloads specialized for speed.
    ///
    /// - Complexity: O(*t*) to create. Iterating is O(*n*) for *n* entities in the smallest
    ///   queried or required type.
    @inlinable
    public func query<each C: Component>(_ types: repeat (each C).Type) -> QueryView<repeat each C> {
        QueryView(world: self, filter: QueryFilter()) { world in
            world.packReader(repeat (each C).self) { entity, components in (entity: entity, repeat each components) }
        }
    }

    /// The entities holding an `A`, with it, lazily.
    ///
    /// - Complexity: O(1) to create. Iterating is O(*n*) for *n* entities in the smallest
    ///   queried or required type.
    @inlinable
    public func query<A: Component>(_ a: A.Type) -> QueryView<A> {
        QueryView(world: self, filter: QueryFilter()) { world in
            world.reader(A.self) { entity, a in (entity: entity, a) }
        }
    }

    /// The entities holding an `A` and a `B`, with them, lazily.
    ///
    /// - Complexity: O(1) to create. Iterating is O(*n*) for *n* entities in the smallest
    ///   queried or required type.
    @inlinable
    public func query<A: Component, B: Component>(_ a: A.Type, _ b: B.Type) -> QueryView<A, B> {
        QueryView(world: self, filter: QueryFilter()) { world in
            world.reader(A.self, B.self) { entity, a, b in (entity: entity, a, b) }
        }
    }

    /// The entities holding an `A`, a `B` and a `C`, with them, lazily.
    ///
    /// - Complexity: O(1) to create. Iterating is O(*n*) for *n* entities in the smallest
    ///   queried or required type.
    @inlinable
    public func query<A: Component, B: Component, C: Component>(_ a: A.Type, _ b: B.Type, _ c: C.Type) -> QueryView<A, B, C> {
        QueryView(world: self, filter: QueryFilter()) { world in
            world.reader(A.self, B.self, C.self) { entity, a, b, c in (entity: entity, a, b, c) }
        }
    }
}

/// The live entities passing a filter, lazily: a query of no component types.
///
/// Like ``QueryView``, a view is a snapshot of the world it came from.
///
/// ```swift
/// for entity in world.query().with(Player.self).without(Dead.self) {
///     print(entity)
/// }
/// ```
@frozen
public struct EntityQueryView: Sequence, Sendable {
    @usableFromInline let world: World
    /// The types the entities must hold and must not hold.
    public let filter: QueryFilter

    @inlinable
    init(world: World, filter: QueryFilter) {
        self.world = world
        self.filter = filter
    }

    /// This view, keeping only entities that also hold every one of `types`.
    @inlinable
    public func with<each F: Component>(_ types: repeat (each F).Type) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.with(repeat each types))
    }

    /// This view, keeping only entities that hold none of `types`.
    @inlinable
    public func without<each F: Component>(_ types: repeat (each F).Type) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.without(repeat each types))
    }

    /// This view, keeping only entities whose `F` was added after `since` (nil for the world's
    /// ``World/lastRun``).
    @inlinable
    public func added<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.added(F.self, since: since))
    }

    /// This view, keeping only entities whose `F` was added or changed after `since` (nil for the
    /// world's ``World/lastRun``).
    @inlinable
    public func changed<F: Component>(_ type: F.Type, since: ChangeTick? = nil) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.changed(F.self, since: since))
    }

    /// This view, keeping only entities that at least one of `filters` passes.
    @inlinable
    public func anyOf(_ filters: QueryFilter...) -> EntityQueryView {
        EntityQueryView(world: world, filter: filter.anyOf(filters))
    }

    /// This view, keeping only entities that `filter` passes as well.
    @inlinable
    public func filtered(by filter: QueryFilter) -> EntityQueryView {
        EntityQueryView(world: world, filter: self.filter.merging(filter))
    }

    /// The number of entities.
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

    /// Steps through the entities.
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline let filter: ResolvedFilter
        @usableFromInline let driver: [Entity]
        @usableFromInline var cursor = 0

        @inlinable
        init(world: World, filter: QueryFilter) {
            let resolved = ResolvedFilter(filter, in: world)
            var driver: [Entity]? = nil
            for index in resolved.candidates where driver == nil || index.dense.count < driver!.count {
                driver = index.dense
            }
            self.filter = resolved
            self.driver = resolved.isUnsatisfiable ? [] : driver ?? Array(world.entities)
        }

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

    @inlinable
    public func makeIterator() -> Iterator { Iterator(world: world, filter: filter) }
}

extension World {
    /// The live entities, lazily, to be narrowed with ``EntityQueryView/with(_:)`` and
    /// ``EntityQueryView/without(_:)``.
    ///
    /// - Complexity: O(1) to create.
    @inlinable
    public func query() -> EntityQueryView {
        EntityQueryView(world: self, filter: QueryFilter())
    }
}
