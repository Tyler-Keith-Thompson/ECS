extension World {
    /// Changes the `W` of every entity that holds one, every type in `reading` and passes
    /// `filter`, in place.
    ///
    /// `body` receives the `W` to change and a row of the entity with the components it reads.
    /// Entities are visited in the storage order of whichever of these types the fewest entities
    /// hold. Every `W` visited is marked changed at the current ``changeTick``.
    ///
    /// ```swift
    /// world.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, row in
    ///     position.x += row.components.dx
    /// }
    /// ```
    ///
    /// Updates reading one, two or three types have overloads specialized for speed.
    ///
    /// - Parameters:
    ///   - type: The component type to change.
    ///   - reading: Component types the entity must hold, passed to `body` in this order.
    ///   - filter: Further types the entity must hold or must not hold.
    ///   - body: Changes one entity's `W`. If it throws, the visit stops; changes already made
    ///     are kept.
    /// - Complexity: O(*n*) for *n* entities in the smallest of the types, plus a copy of the
    ///   `W` storage when another world shares it.
    /// - Precondition: `reading` does not list `W`.
    @inlinable
    public mutating func update<W: Component, each R: Component, Failure: Error>(
        _ type: W.Type,
        reading: repeat (each R).Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout W, QueryRow<repeat each R>) throws(Failure) -> Void
    ) throws(Failure) {
        var reads: [ObjectIdentifier] = []
        for read in repeat (each R).self {
            reads.append(ObjectIdentifier(read))
        }
        try update(W.self, reads: reads, reader: { world in world.packReader(repeat (each R).self) { entity, components in QueryRow(entity: entity, components: (repeat each components)) } }, filter: filter, body: body)
    }

    /// Changes the `W` of every entity holding one and the read types, in place; see
    /// ``update(_:reading:where:body:)``.
    @inlinable
    public mutating func update<W: Component, R1: Component, Failure: Error>(
        _ type: W.Type,
        reading r1: R1.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout W, QueryRow<R1>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(W.self, reads: [ObjectIdentifier(R1.self)], reader: { world in world.reader(R1.self) { QueryRow(entity: $0, components: $1) } }, filter: filter, body: body)
    }

    /// Changes the `W` of every entity holding one and the read types, in place; see
    /// ``update(_:reading:where:body:)``.
    @inlinable
    public mutating func update<W: Component, R1: Component, R2: Component, Failure: Error>(
        _ type: W.Type,
        reading r1: R1.Type, _ r2: R2.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout W, QueryRow<R1, R2>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(W.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self)], reader: { world in world.reader(R1.self, R2.self) { QueryRow(entity: $0, components: ($1, $2)) } }, filter: filter, body: body)
    }

    /// Changes the `W` of every entity holding one and the read types, in place; see
    /// ``update(_:reading:where:body:)``.
    @inlinable
    public mutating func update<W: Component, R1: Component, R2: Component, R3: Component, Failure: Error>(
        _ type: W.Type,
        reading r1: R1.Type, _ r2: R2.Type, _ r3: R3.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout W, QueryRow<R1, R2, R3>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(W.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self), ObjectIdentifier(R3.self)], reader: { world in world.reader(R1.self, R2.self, R3.self) { QueryRow(entity: $0, components: ($1, $2, $3)) } }, filter: filter, body: body)
    }

    /// Changes the `A` and `B` of every entity that holds both, every type in `reading` and
    /// passes `filter`, in place. Every `A` and `B` visited is marked changed at the current
    /// ``changeTick``.
    ///
    /// ```swift
    /// world.update(Health.self, Stamina.self, reading: Regeneration.self) { health, stamina, row in
    ///     health.current += row.components.health
    ///     stamina.current += row.components.stamina
    /// }
    /// ```
    ///
    /// Updates reading one, two or three types have overloads specialized for speed.
    ///
    /// - Parameters:
    ///   - first: The first component type to change.
    ///   - second: The second component type to change.
    ///   - reading: Component types the entity must hold, passed to `body` in this order.
    ///   - filter: Further types the entity must hold or must not hold.
    ///   - body: Changes one entity's `A` and `B`. If it throws, the visit stops; changes already
    ///     made are kept.
    /// - Complexity: O(*n*) for *n* entities in the smallest of the types, plus a copy of the
    ///   storage of `A` or `B` when another world shares it.
    /// - Precondition: `A` and `B` differ, and `reading` lists neither.
    @inlinable
    public mutating func update<A: Component, B: Component, each R: Component, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        reading: repeat (each R).Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout A, inout B, QueryRow<repeat each R>) throws(Failure) -> Void
    ) throws(Failure) {
        var reads: [ObjectIdentifier] = []
        for read in repeat (each R).self {
            reads.append(ObjectIdentifier(read))
        }
        try update(A.self, B.self, reads: reads, reader: { world in world.packReader(repeat (each R).self) { entity, components in QueryRow(entity: entity, components: (repeat each components)) } }, filter: filter, body: body)
    }

    /// Changes the `A` and `B` of every entity holding both and the read types, in place; see
    /// ``update(_:_:reading:where:body:)``.
    @inlinable
    public mutating func update<A: Component, B: Component, R1: Component, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        reading r1: R1.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout A, inout B, QueryRow<R1>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(A.self, B.self, reads: [ObjectIdentifier(R1.self)], reader: { world in world.reader(R1.self) { QueryRow(entity: $0, components: $1) } }, filter: filter, body: body)
    }

    /// Changes the `A` and `B` of every entity holding both and the read types, in place; see
    /// ``update(_:_:reading:where:body:)``.
    @inlinable
    public mutating func update<A: Component, B: Component, R1: Component, R2: Component, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        reading r1: R1.Type, _ r2: R2.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout A, inout B, QueryRow<R1, R2>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(A.self, B.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self)], reader: { world in world.reader(R1.self, R2.self) { QueryRow(entity: $0, components: ($1, $2)) } }, filter: filter, body: body)
    }

    /// Changes the `A` and `B` of every entity holding both and the read types, in place; see
    /// ``update(_:_:reading:where:body:)``.
    @inlinable
    public mutating func update<A: Component, B: Component, R1: Component, R2: Component, R3: Component, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        reading r1: R1.Type, _ r2: R2.Type, _ r3: R3.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout A, inout B, QueryRow<R1, R2, R3>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(A.self, B.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self), ObjectIdentifier(R3.self)], reader: { world in world.reader(R1.self, R2.self, R3.self) { QueryRow(entity: $0, components: ($1, $2, $3)) } }, filter: filter, body: body)
    }

    // MARK: The visits

    /// Visits every entity holding a `W`, the read types and passing `filter`, changing its `W`.
    @inlinable
    mutating func update<W: Component, each R, Failure: Error>(
        _ type: W.Type,
        reads: [ObjectIdentifier],
        reader makeReader: (World) -> Reader<QueryRow<repeat each R>>,
        filter: QueryFilter,
        body: (inout W, QueryRow<repeat each R>) throws(Failure) -> Void
    ) throws(Failure) {
        precondition(!reads.contains(ObjectIdentifier(W.self)), "update reads the \(W.self) it writes")
        guard let slot = columnPositions.position(of: ObjectIdentifier(W.self)) else { return }
        let resolved = ResolvedFilter(filter, in: self, touching: reads + [ObjectIdentifier(W.self)])
        guard !resolved.isUnsatisfiable else { return }
        let reader = makeReader(self)
        let column = uniqueColumn(at: slot, of: W.self)
        // Moved out for the visit so writes reach the storage directly and are not copied; the
        // ticks before the index is copied, which would otherwise share them.
        var values: [W] = []
        var ticks: [ComponentTicks] = []
        swap(&values, &column.values)
        swap(&ticks, &column.index.ticks)
        defer {
            swap(&values, &column.values)
            swap(&ticks, &column.index.ticks)
        }
        let index = column.index
        let tick = changeTick

        // The column walked: -2 for W, k for the k-th read type, -1 for a filter type.
        var driver = index.dense
        var driverColumn = -2
        for (column, entities) in reader.columns.enumerated() where entities.count < driver.count {
            driver = entities
            driverColumn = column
        }
        for required in resolved.candidates where required.dense.count < driver.count {
            driver = required.dense
            driverColumn = -1
        }
        var end = driver.count
        if let aligned = alignedCount(of: [ObjectIdentifier(W.self)] + reader.types) {
            driver = index.dense
            driverColumn = alignedDriver
            end = aligned
        }
        let checksFilter = !resolved.isEmpty

        // Through buffer pointers, so the loop pays no uniqueness or bounds check per write.
        try ticks.withUnsafeMutableBufferPointer { ticks throws(Failure) in
            try values.withUnsafeMutableBufferPointer { values throws(Failure) in
                for cursor in 0 ..< end {
                    let entity = driver[cursor]
                    var position = cursor
                    if driverColumn != -2, driverColumn != alignedDriver {
                        guard let found = index.position(of: entity) else { continue }
                        position = found
                    }
                    if checksFilter, !resolved.passes(entity) { continue }
                    guard let row = reader.row(entity, cursor, driverColumn) else { continue }
                    ticks[position].changed = tick
                    try body(&values[position], row)
                }
            }
        }
    }

    /// Visits every entity holding an `A`, a `B`, the read types and passing `filter`, changing
    /// its `A` and `B`.
    @inlinable
    mutating func update<A: Component, B: Component, each R, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        reads: [ObjectIdentifier],
        reader makeReader: (World) -> Reader<QueryRow<repeat each R>>,
        filter: QueryFilter,
        body: (inout A, inout B, QueryRow<repeat each R>) throws(Failure) -> Void
    ) throws(Failure) {
        precondition(ObjectIdentifier(A.self) != ObjectIdentifier(B.self), "update writes \(A.self) twice")
        precondition(
            !reads.contains(ObjectIdentifier(A.self)) && !reads.contains(ObjectIdentifier(B.self)),
            "update reads a type it writes")
        guard let firstSlot = columnPositions.position(of: ObjectIdentifier(A.self)),
              let secondSlot = columnPositions.position(of: ObjectIdentifier(B.self)) else { return }
        let resolved = ResolvedFilter(filter, in: self, touching: reads + [ObjectIdentifier(A.self), ObjectIdentifier(B.self)])
        guard !resolved.isUnsatisfiable else { return }
        let reader = makeReader(self)
        let firstColumn = uniqueColumn(at: firstSlot, of: A.self)
        let secondColumn = uniqueColumn(at: secondSlot, of: B.self)
        var firstValues: [A] = []
        var secondValues: [B] = []
        var firstTicks: [ComponentTicks] = []
        var secondTicks: [ComponentTicks] = []
        swap(&firstValues, &firstColumn.values)
        swap(&secondValues, &secondColumn.values)
        swap(&firstTicks, &firstColumn.index.ticks)
        swap(&secondTicks, &secondColumn.index.ticks)
        defer {
            swap(&firstValues, &firstColumn.values)
            swap(&secondValues, &secondColumn.values)
            swap(&firstTicks, &firstColumn.index.ticks)
            swap(&secondTicks, &secondColumn.index.ticks)
        }
        let firstIndex = firstColumn.index
        let secondIndex = secondColumn.index
        let tick = changeTick

        // The column walked: -2 for A, -3 for B, k for the k-th read type, -1 for a filter type.
        var driver = firstIndex.dense
        var driverColumn = -2
        if secondIndex.dense.count < driver.count {
            driver = secondIndex.dense
            driverColumn = -3
        }
        for (column, entities) in reader.columns.enumerated() where entities.count < driver.count {
            driver = entities
            driverColumn = column
        }
        for required in resolved.candidates where required.dense.count < driver.count {
            driver = required.dense
            driverColumn = -1
        }
        var end = driver.count
        if let aligned = alignedCount(of: [ObjectIdentifier(A.self), ObjectIdentifier(B.self)] + reader.types) {
            driver = firstIndex.dense
            driverColumn = alignedDriver
            end = aligned
        }
        let checksFilter = !resolved.isEmpty

        // Through buffer pointers, so the loop pays no uniqueness or bounds check per write.
        try firstTicks.withUnsafeMutableBufferPointer { firstTicks throws(Failure) in
            try secondTicks.withUnsafeMutableBufferPointer { secondTicks throws(Failure) in
                try firstValues.withUnsafeMutableBufferPointer { firstValues throws(Failure) in
                    try secondValues.withUnsafeMutableBufferPointer { secondValues throws(Failure) in
                        for cursor in 0 ..< end {
                            let entity = driver[cursor]
                            var firstPosition = cursor
                            var secondPosition = cursor
                            if driverColumn != -2, driverColumn != alignedDriver {
                                guard let found = firstIndex.position(of: entity) else { continue }
                                firstPosition = found
                            }
                            if driverColumn != -3, driverColumn != alignedDriver {
                                guard let found = secondIndex.position(of: entity) else { continue }
                                secondPosition = found
                            }
                            if checksFilter, !resolved.passes(entity) { continue }
                            guard let row = reader.row(entity, cursor, driverColumn) else { continue }
                            firstTicks[firstPosition].changed = tick
                            secondTicks[secondPosition].changed = tick
                            try body(&firstValues[firstPosition], &secondValues[secondPosition], row)
                        }
                    }
                }
            }
        }
    }

    /// Visits every entity holding an `A`, a `B`, a `C`, the read types and passing `filter`,
    /// changing its `A`, `B` and `C`.
    @inlinable
    mutating func update<A: Component, B: Component, C: Component, each R, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        _ third: C.Type,
        reads: [ObjectIdentifier],
        reader makeReader: (World) -> Reader<QueryRow<repeat each R>>,
        filter: QueryFilter,
        body: (inout A, inout B, inout C, QueryRow<repeat each R>) throws(Failure) -> Void
    ) throws(Failure) {
        let written = [ObjectIdentifier(A.self), ObjectIdentifier(B.self), ObjectIdentifier(C.self)]
        precondition(Set(written).count == 3, "update writes a type twice")
        precondition(!reads.contains(where: written.contains), "update reads a type it writes")
        guard let firstSlot = columnPositions.position(of: ObjectIdentifier(A.self)),
              let secondSlot = columnPositions.position(of: ObjectIdentifier(B.self)),
              let thirdSlot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return }
        let resolved = ResolvedFilter(filter, in: self, touching: reads + written)
        guard !resolved.isUnsatisfiable else { return }
        let reader = makeReader(self)
        let firstColumn = uniqueColumn(at: firstSlot, of: A.self)
        let secondColumn = uniqueColumn(at: secondSlot, of: B.self)
        let thirdColumn = uniqueColumn(at: thirdSlot, of: C.self)
        var firstValues: [A] = []
        var secondValues: [B] = []
        var thirdValues: [C] = []
        var firstTicks: [ComponentTicks] = []
        var secondTicks: [ComponentTicks] = []
        var thirdTicks: [ComponentTicks] = []
        swap(&firstValues, &firstColumn.values)
        swap(&secondValues, &secondColumn.values)
        swap(&thirdValues, &thirdColumn.values)
        swap(&firstTicks, &firstColumn.index.ticks)
        swap(&secondTicks, &secondColumn.index.ticks)
        swap(&thirdTicks, &thirdColumn.index.ticks)
        defer {
            swap(&firstValues, &firstColumn.values)
            swap(&secondValues, &secondColumn.values)
            swap(&thirdValues, &thirdColumn.values)
            swap(&firstTicks, &firstColumn.index.ticks)
            swap(&secondTicks, &secondColumn.index.ticks)
            swap(&thirdTicks, &thirdColumn.index.ticks)
        }
        let firstIndex = firstColumn.index
        let secondIndex = secondColumn.index
        let thirdIndex = thirdColumn.index
        let tick = changeTick

        // The column walked: -2 for A, -3 for B, -4 for C, k for the k-th read type, -1 for a
        // filter type.
        var driver = firstIndex.dense
        var driverColumn = -2
        if secondIndex.dense.count < driver.count {
            driver = secondIndex.dense
            driverColumn = -3
        }
        if thirdIndex.dense.count < driver.count {
            driver = thirdIndex.dense
            driverColumn = -4
        }
        for (column, entities) in reader.columns.enumerated() where entities.count < driver.count {
            driver = entities
            driverColumn = column
        }
        for required in resolved.candidates where required.dense.count < driver.count {
            driver = required.dense
            driverColumn = -1
        }
        var end = driver.count
        if let aligned = alignedCount(of: written + reader.types) {
            driver = firstIndex.dense
            driverColumn = alignedDriver
            end = aligned
        }
        let checksFilter = !resolved.isEmpty

        // Through buffer pointers, so the loop pays no uniqueness or bounds check per write.
        try firstTicks.withUnsafeMutableBufferPointer { firstTicks throws(Failure) in
            try secondTicks.withUnsafeMutableBufferPointer { secondTicks throws(Failure) in
                try thirdTicks.withUnsafeMutableBufferPointer { thirdTicks throws(Failure) in
                    try firstValues.withUnsafeMutableBufferPointer { firstValues throws(Failure) in
                        try secondValues.withUnsafeMutableBufferPointer { secondValues throws(Failure) in
                            try thirdValues.withUnsafeMutableBufferPointer { thirdValues throws(Failure) in
                                for cursor in 0 ..< end {
                                    let entity = driver[cursor]
                                    var firstPosition = cursor
                                    var secondPosition = cursor
                                    var thirdPosition = cursor
                                    if driverColumn != -2, driverColumn != alignedDriver {
                                        guard let found = firstIndex.position(of: entity) else { continue }
                                        firstPosition = found
                                    }
                                    if driverColumn != -3, driverColumn != alignedDriver {
                                        guard let found = secondIndex.position(of: entity) else { continue }
                                        secondPosition = found
                                    }
                                    if driverColumn != -4, driverColumn != alignedDriver {
                                        guard let found = thirdIndex.position(of: entity) else { continue }
                                        thirdPosition = found
                                    }
                                    if checksFilter, !resolved.passes(entity) { continue }
                                    guard let row = reader.row(entity, cursor, driverColumn) else { continue }
                                    firstTicks[firstPosition].changed = tick
                                    secondTicks[secondPosition].changed = tick
                                    thirdTicks[thirdPosition].changed = tick
                                    try body(&firstValues[firstPosition], &secondValues[secondPosition], &thirdValues[thirdPosition], row)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
