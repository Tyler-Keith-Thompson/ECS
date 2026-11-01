extension World {
    // MARK: Spawning many entities

    /// Creates an entity for each component in a sequence and returns their handles.
    ///
    /// Spawning many entities at once does the same as spawning each with ``spawn(_:)-5h8u``, in
    /// order, but faster when nothing watches the spawns: the world finds the type's storage
    /// once and grows it once, rather than once per entity. Use it to build a large world, such
    /// as a simulation's initial state:
    ///
    /// ```swift
    /// var world = World()
    /// let rocks = world.spawn(contentsOf: (0 ..< 3).map { Position(x: Double($0), y: 0) })
    ///
    /// print(rocks.count, world[Position.self, of: rocks[2]].x)
    /// // Prints "3 2.0"
    /// ```
    ///
    /// The faster path applies when the world has no hooks or cached queries, and the type
    /// requires no other components and has no relation, value index, group or change log. Otherwise
    /// the world spawns the entities one at a time, so hooks run and every structure stays
    /// current either way.
    ///
    /// - Parameter components: The components, one for each new entity.
    /// - Returns: The handles of the new entities, in the order of `components`.
    /// - Complexity: O(*n*) amortized for *n* components.
    /// - Precondition: Fewer than `UInt32.max` slots are in use.
    @inlinable
    @discardableResult
    public mutating func spawn<A: Component>(contentsOf components: some Sequence<A>) -> [Entity] {
        let components = Array(components)
        guard let slot = batchSlot(of: A.self) else {
            return components.map { spawn($0) }
        }
        let entities = makeEntities(count: components.count)
        appendBatch(components, for: entities, slot: slot)
        return entities
    }

    /// Creates an entity for each pair of components in a sequence and returns their handles.
    ///
    /// This method behaves like ``spawn(contentsOf:)-6qu8f``, spawning each entity with
    /// ``spawn(_:)-5h8u`` given both components:
    ///
    /// ```swift
    /// var world = World()
    /// let movers = world.spawn(contentsOf: (0 ..< 3).map { index in
    ///     (Position(x: 0, y: 0), Velocity(dx: Double(index), dy: 0))
    /// })
    ///
    /// print(world[Velocity.self, of: movers[1]].dx)
    /// // Prints "1.0"
    /// ```
    ///
    /// - Parameter rows: The components, a pair for each new entity.
    /// - Returns: The handles of the new entities, in the order of `rows`.
    /// - Complexity: O(*n*) amortized for *n* pairs.
    /// - Precondition: Fewer than `UInt32.max` slots are in use.
    @inlinable
    @discardableResult
    public mutating func spawn<A: Component, B: Component>(contentsOf rows: some Sequence<(A, B)>) -> [Entity] {
        let rows = Array(rows)
        guard ObjectIdentifier(A.self) != ObjectIdentifier(B.self),
              let first = batchSlot(of: A.self), let second = batchSlot(of: B.self) else {
            return rows.map { spawn($0.0, $0.1) }
        }
        let entities = makeEntities(count: rows.count)
        appendBatch(rows.map(\.0), for: entities, slot: first)
        appendBatch(rows.map(\.1), for: entities, slot: second)
        return entities
    }

    /// Creates an entity for each triple of components in a sequence and returns their handles.
    ///
    /// This method behaves like ``spawn(contentsOf:)-6qu8f``, spawning each entity with
    /// ``spawn(_:)-5h8u`` given all three components.
    ///
    /// - Parameter rows: The components, a triple for each new entity.
    /// - Returns: The handles of the new entities, in the order of `rows`.
    /// - Complexity: O(*n*) amortized for *n* triples.
    /// - Precondition: Fewer than `UInt32.max` slots are in use.
    @inlinable
    @discardableResult
    public mutating func spawn<A: Component, B: Component, C: Component>(contentsOf rows: some Sequence<(A, B, C)>) -> [Entity] {
        let rows = Array(rows)
        let types = [ObjectIdentifier(A.self), ObjectIdentifier(B.self), ObjectIdentifier(C.self)]
        guard Set(types).count == 3, let first = batchSlot(of: A.self), let second = batchSlot(of: B.self),
              let third = batchSlot(of: C.self) else {
            return rows.map { spawn($0.0, $0.1, $0.2) }
        }
        let entities = makeEntities(count: rows.count)
        appendBatch(rows.map(\.0), for: entities, slot: first)
        appendBatch(rows.map(\.1), for: entities, slot: second)
        appendBatch(rows.map(\.2), for: entities, slot: third)
        return entities
    }

    /// Creates an entity for each bundle in a sequence and returns their handles.
    ///
    /// This method spawns each entity with ``spawn(_:)-13jpz``, in order, reserving room for the
    /// entities first:
    ///
    /// ```swift
    /// struct Rock: Bundle {
    ///     var x: Double
    ///     var body: some Bundle {
    ///         Position(x: x, y: 0)
    ///         Health(current: 5)
    ///     }
    /// }
    ///
    /// var world = World()
    /// let rocks = world.spawn(contentsOf: [Rock(x: 1), Rock(x: 2)])
    /// print(world[Position.self, of: rocks[1]].x)
    /// // Prints "2.0"
    /// ```
    ///
    /// - Parameter bundles: The bundles, one for each new entity.
    /// - Returns: The handles of the new entities, in the order of `bundles`.
    /// - Complexity: O(*n*·*k*) amortized for *n* bundles of *k* components.
    /// - Precondition: Fewer than `UInt32.max` slots are in use.
    @inlinable
    @discardableResult
    public mutating func spawn<B: Bundle>(contentsOf bundles: some Sequence<B>) -> [Entity] {
        let count = bundles.underestimatedCount
        generations.reserveCapacity(generations.count + count)
        isLive.reserveCapacity(isLive.count + count)
        var entities: [Entity] = []
        entities.reserveCapacity(count)
        for bundle in bundles {
            entities.append(spawn(bundle))
        }
        return entities
    }

    /// The position of `C`'s column when storing many components of it at once can skip the
    /// per-entity bookkeeping, or nil when something must see each spawn.
    @inlinable
    mutating func batchSlot<C: Component>(of type: C.Type) -> Int? {
        guard hooks.isEmpty, caches.isEmpty, C.Required.self == TupleBundle< >.self else { return nil }
        let slot = columnSlot(of: C.self)
        let column = columns[slot]
        guard !column.isRelation, !column.isIndexed, column.group < 0, column.changeLog == nil else { return nil }
        return slot
    }

    /// Makes `count` new live entities, reusing vacant slots first.
    @inlinable
    mutating func makeEntities(count: Int) -> [Entity] {
        var entities: [Entity] = []
        entities.reserveCapacity(count)
        structureVersion &+= UInt64(truncatingIfNeeded: count)
        while entities.count < count, let slot = vacant.popLast() {
            isLive[Int(slot)] = true
            entities.append(Entity(index: slot, generation: generations[Int(slot)]))
        }
        let fresh = count - entities.count
        precondition(generations.count + fresh < Int(UInt32.max), "A world holds at most \(UInt32.max) slots")
        let first = generations.count
        generations.append(contentsOf: repeatElement(0, count: fresh))
        isLive.append(contentsOf: repeatElement(true, count: fresh))
        for slot in first ..< first + fresh {
            entities.append(Entity(index: UInt32(slot), generation: 0))
        }
        return entities
    }

    /// Stores `values` for `entities`, new entities holding no `C`, in the column at `slot`.
    @inlinable
    mutating func appendBatch<C: Component>(_ values: [C], for entities: [Entity], slot: Int) {
        let column = uniqueColumn(at: slot, of: C.self)
        column.index.append(contentsOf: entities, at: changeTick)
        column.values.append(contentsOf: values)
    }
}
