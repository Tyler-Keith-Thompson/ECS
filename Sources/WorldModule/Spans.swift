extension World {
    /// Calls `body` with every entity holding a `C` and their components, as spans in storage
    /// order: the component at each position belongs to the entity at the same position.
    ///
    /// The spans reach the storage directly, for loops the compiler can vectorize and for C
    /// functions taking a pointer and a count. They include entities a query would skip, such as
    /// ``Disabled`` ones.
    ///
    /// ```swift
    /// let total = world.withSpan(of: Health.self) { _, health in
    ///     var sum = 0
    ///     for position in health.indices { sum += health[position].current }
    ///     return sum
    /// }
    /// ```
    ///
    /// - Returns: What `body` returns.
    /// - Complexity: O(1) besides `body`.
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

    /// Calls `body` with every entity holding a `C` and their components, the components as a
    /// mutable span, and marks every `C` changed at the current ``changeTick``; see
    /// ``withSpan(of:_:)``.
    ///
    /// ```swift
    /// world.withMutableSpan(of: Position.self) { _, positions in
    ///     for position in positions.indices { positions[position].x += 1 }
    /// }
    /// ```
    ///
    /// - Returns: What `body` returns.
    /// - Complexity: O(*n*) for *n* entities holding a `C`, plus a copy of the `C` storage when
    ///   another world shares it.
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
