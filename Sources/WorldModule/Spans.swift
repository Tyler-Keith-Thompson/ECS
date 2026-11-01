extension World {
    /// Calls the given closure with the storage of a component type, as spans of entities and
    /// their components.
    ///
    /// The spans give direct access to the world's storage, in storage order: the component at
    /// each position belongs to the entity at the same position. Use this method for loops the
    /// compiler can vectorize, and for C functions that take a pointer and a count. The following
    /// example adds up the health of every entity:
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Health(current: 10))
    /// world.spawn(Health(current: 25))
    ///
    /// let total = world.withSpan(of: Health.self) { _, health in
    ///     var sum = 0
    ///     for position in health.indices { sum += health[position].current }
    ///     return sum
    /// }
    /// print(total)
    /// // Prints "35"
    /// ```
    ///
    /// The spans include entities that a query would skip, such as ``Disabled`` ones. When the
    /// world has never stored a component of the type, both spans are empty.
    ///
    /// - Parameters:
    ///   - type: The component type whose storage to read.
    ///   - body: A closure that takes the entities holding a component of type `type` and their
    ///     components. The spans are valid only for the duration of the closure.
    /// - Returns: The value `body` returns.
    /// - Throws: The error `body` throws, if any.
    /// - Complexity: O(1), besides the cost of `body`.
    @inlinable
    public func withSpan<C: Component, Result, Failure: Error>(
        of type: C.Type,
        _ body: (Span<Entity>, Span<C>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else {
            let entities: [Entity] = []
            let values: [C] = []
            return try Self.withSpans(entities, values, body)
        }
        let column = unsafeDowncast(columns[slot], to: Column<C>.self)
        return try Self.withSpans(column.index.dense, column.values, body)
    }

    /// Calls the given closure with the storage of a component type, as a span of entities and a
    /// mutable span of their components.
    ///
    /// Use this method to change every component of a type in a tight loop. As in
    /// ``withSpan(of:_:)``, the component at each position belongs to the entity at the same
    /// position, and the spans include entities that a query would skip:
    ///
    /// ```swift
    /// var world = World()
    /// let ball = world.spawn(Position(x: 0, y: 0))
    ///
    /// world.withMutableSpan(of: Position.self) { _, positions in
    ///     for position in positions.indices { positions[position].x += 1 }
    /// }
    /// print(world[Position.self, of: ball])
    /// // Prints "Position(x: 1.0, y: 0.0)"
    /// ```
    ///
    /// Every component of the type is marked changed at the current ``changeTick``, whether or not
    /// the closure changes it.
    ///
    /// - Parameters:
    ///   - type: The component type whose storage to change.
    ///   - body: A closure that takes the entities holding a component of type `type` and a
    ///     mutable span of their components. The spans are valid only for the duration of the
    ///     closure.
    /// - Returns: The value `body` returns.
    /// - Throws: The error `body` throws, if any.
    /// - Complexity: O(*n*), where *n* is the number of entities holding a component of type
    ///   `type`, plus a copy of that storage when another world shares it.
    @inlinable
    public mutating func withMutableSpan<C: Component, Result, Failure: Error>(
        of type: C.Type,
        _ body: (Span<Entity>, inout MutableSpan<C>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else {
            let entities: [Entity] = []
            var values: [C] = []
            return try Self.withMutableSpans(entities, &values, body)
        }
        let column = uniqueColumn(at: slot, of: C.self)
        let tick = changeTick
        defer {
            for position in column.index.ticks.indices {
                column.index.ticks[position].changed = tick
            }
            if column.changeLog != nil {
                let index = column.index
                column.changeLog!.record(changesOf: index.dense, upTo: index.dense.count, at: tick, index: index, ticks: index.ticks)
            }
        }
        return try Self.withMutableSpans(column.index.dense, &column.values, body)
    }

    @inlinable
    static func withSpans<C, Result, Failure: Error>(
        _ entities: [Entity], _ values: [C],
        _ body: (Span<Entity>, Span<C>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try entities.withUnsafeBufferPointer { entities throws(Failure) in
            try values.withUnsafeBufferPointer { values throws(Failure) in
                try body(Span(_unsafeElements: entities), Span(_unsafeElements: values))
            }
        }
    }

    @inlinable
    static func withMutableSpans<C, Result, Failure: Error>(
        _ entities: [Entity], _ values: inout [C],
        _ body: (Span<Entity>, inout MutableSpan<C>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try entities.withUnsafeBufferPointer { entities throws(Failure) in
            try values.withUnsafeMutableBufferPointer { values throws(Failure) in
                var span = MutableSpan(_unsafeElements: values)
                return try body(Span(_unsafeElements: entities), &span)
            }
        }
    }
}
