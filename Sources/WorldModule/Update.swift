extension World {
    /// Changes a component of every entity that holds it and the given read types, in place.
    ///
    /// Use this method to apply the same change to many entities, such as moving everything by its
    /// velocity. The method visits every entity that holds a `W` and every type in `reading`, and
    /// that passes `filter`. For each one, `body` receives the entity's `W` to change and a
    /// ``QueryRow`` carrying the entity and the components it reads:
    ///
    /// ```swift
    /// var world = World()
    /// let comet = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
    /// let statue = world.spawn(Position(x: 5, y: 5), Velocity(dx: 1, dy: 1), Frozen())
    ///
    /// world.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, row in
    ///     position.x += row.components.dx
    ///     position.y += row.components.dy
    /// }
    /// print(world[Position.self, of: comet])
    /// // Prints "Position(x: 1.0, y: 2.0)"
    /// print(world[Position.self, of: statue])
    /// // Prints "Position(x: 5.0, y: 5.0)"
    /// ```
    ///
    /// The update writes each component where it's stored, so no component is copied out and back.
    /// Every `W` visited is marked changed at the world's current ``changeTick``, even if `body`
    /// leaves it as it was. Entities are visited in the storage order of whichever of the types,
    /// written, read or required by `filter`, the fewest entities hold, or of a shorter list where
    /// one applies, such as a target's sources for a relation filter. Updates reading one, two or
    /// three types run through code specialized for that number of types.
    ///
    /// To read ``AnyOf`` groups, pass a ``Query`` to `update(_:over:body:)` instead.
    ///
    /// - Parameters:
    ///   - type: The component type to change.
    ///   - reading: The component types an entity must also hold, which `body` receives in this
    ///     order.
    ///   - filter: Further conditions an entity must meet. The default passes every entity.
    ///   - body: A closure that changes one entity's component. If it throws, the visit stops and
    ///     the method rethrows the error; changes already made are kept.
    /// - Complexity: O(*n*) for *n* entities in the smallest of the types, plus a copy of the `W`
    ///   storage when another world shares it.
    /// - Precondition: `reading` doesn't list `W`.
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

    /// Changes a component of every entity that holds it and the given read types, in place.
    ///
    /// See `update(_:reading:where:body:)` for how a visit proceeds.
    @inlinable
    public mutating func update<W: Component, R1: Component, Failure: Error>(
        _ type: W.Type,
        reading r1: R1.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout W, QueryRow<R1>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(W.self, reads: [ObjectIdentifier(R1.self)], reader: { world in world.reader(R1.self) { QueryRow(entity: $0, components: $1) } }, filter: filter, body: body)
    }

    /// Changes a component of every entity that holds it and the given read types, in place.
    ///
    /// See `update(_:reading:where:body:)` for how a visit proceeds.
    @inlinable
    public mutating func update<W: Component, R1: Component, R2: Component, Failure: Error>(
        _ type: W.Type,
        reading r1: R1.Type, _ r2: R2.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout W, QueryRow<R1, R2>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(W.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self)], reader: { world in world.reader(R1.self, R2.self) { QueryRow(entity: $0, components: ($1, $2)) } }, filter: filter, body: body)
    }

    /// Changes a component of every entity that holds it and the given read types, in place.
    ///
    /// See `update(_:reading:where:body:)` for how a visit proceeds.
    @inlinable
    public mutating func update<W: Component, R1: Component, R2: Component, R3: Component, Failure: Error>(
        _ type: W.Type,
        reading r1: R1.Type, _ r2: R2.Type, _ r3: R3.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout W, QueryRow<R1, R2, R3>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(W.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self), ObjectIdentifier(R3.self)], reader: { world in world.reader(R1.self, R2.self, R3.self) { QueryRow(entity: $0, components: ($1, $2, $3)) } }, filter: filter, body: body)
    }

    /// Changes two components of every entity that holds both and the given read types, in place.
    ///
    /// The method visits every entity that holds an `A`, a `B` and every type in `reading`, and
    /// that passes `filter`. Every `A` and `B` visited is marked changed at the world's current
    /// ``changeTick``. The following example declares stamina and a regeneration rate, then
    /// restores both health and stamina:
    ///
    /// ```swift
    /// struct Stamina: Component { var current: Int }
    /// struct Regeneration: Component { var health: Int, stamina: Int }
    /// ```
    ///
    /// ```swift
    /// var world = World()
    /// let hero = world.spawn(Health(current: 5), Stamina(current: 2), Regeneration(health: 1, stamina: 3))
    ///
    /// world.update(Health.self, Stamina.self, reading: Regeneration.self) { health, stamina, row in
    ///     health.current += row.components.health
    ///     stamina.current += row.components.stamina
    /// }
    /// print(world[Health.self, of: hero].current, world[Stamina.self, of: hero].current)
    /// // Prints "6 5"
    /// ```
    ///
    /// - Parameters:
    ///   - first: The first component type to change.
    ///   - second: The second component type to change.
    ///   - reading: The component types an entity must also hold, which `body` receives in this
    ///     order.
    ///   - filter: Further conditions an entity must meet. The default passes every entity.
    ///   - body: A closure that changes one entity's components. If it throws, the visit stops and
    ///     the method rethrows the error; changes already made are kept.
    /// - Complexity: O(*n*) for *n* entities in the smallest of the types, plus a copy of the
    ///   storage of `A` or `B` when another world shares it.
    /// - Precondition: `A` and `B` are different types, and `reading` lists neither.
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

    /// Changes two components of every entity that holds both and the given read types, in place.
    ///
    /// See `update(_:_:reading:where:body:)` for how a visit proceeds.
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

    /// Changes two components of every entity that holds both and the given read types, in place.
    ///
    /// See `update(_:_:reading:where:body:)` for how a visit proceeds.
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

    /// Changes two components of every entity that holds both and the given read types, in place.
    ///
    /// See `update(_:_:reading:where:body:)` for how a visit proceeds.
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

    /// Changes three components of every entity that holds all three and the given read types,
    /// in place.
    ///
    /// The method visits every entity that holds an `A`, a `B`, a `C` and every type in
    /// `reading`, and that passes `filter`. Every `A`, `B` and `C` visited is marked changed at
    /// the world's current ``changeTick``. The following example moves each entity, slows it
    /// down and wears down its health, in one pass:
    ///
    /// ```swift
    /// var world = World()
    /// let cart = world.spawn(Position(x: 0, y: 0), Velocity(dx: 4, dy: 0), Health(current: 10))
    ///
    /// world.update(Position.self, Velocity.self, Health.self) { position, velocity, health, _ in
    ///     position.x += velocity.dx
    ///     velocity.dx /= 2
    ///     health.current -= 1
    /// }
    /// print(world[Position.self, of: cart].x, world[Velocity.self, of: cart].dx, world[Health.self, of: cart].current)
    /// // Prints "4.0 2.0 9"
    /// ```
    ///
    /// To change three components over a ``Query``, use `update(_:_:_:over:body:)`.
    ///
    /// - Parameters:
    ///   - first: The first component type to change.
    ///   - second: The second component type to change.
    ///   - third: The third component type to change.
    ///   - reading: The component types an entity must also hold, which `body` receives in this
    ///     order.
    ///   - filter: Further conditions an entity must meet. The default passes every entity.
    ///   - body: A closure that changes one entity's components. If it throws, the visit stops and
    ///     the method rethrows the error; changes already made are kept.
    /// - Complexity: O(*n*) for *n* entities in the smallest of the types, plus a copy of the
    ///   storage of `A`, `B` or `C` when another world shares it.
    /// - Precondition: `A`, `B` and `C` are different types, and `reading` lists none of them.
    @inlinable
    public mutating func update<A: Component, B: Component, C: Component, each R: Component, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        _ third: C.Type,
        reading: repeat (each R).Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout A, inout B, inout C, QueryRow<repeat each R>) throws(Failure) -> Void
    ) throws(Failure) {
        var reads: [ObjectIdentifier] = []
        for read in repeat (each R).self {
            reads.append(ObjectIdentifier(read))
        }
        try update(A.self, B.self, C.self, reads: reads, reader: { world in world.packReader(repeat (each R).self) { entity, components in QueryRow(entity: entity, components: (repeat each components)) } }, filter: filter, body: body)
    }

    /// Changes three components of every entity that holds all three and the given read types,
    /// in place.
    ///
    /// See `update(_:_:_:reading:where:body:)` for how a visit proceeds.
    @inlinable
    public mutating func update<A: Component, B: Component, C: Component, R1: Component, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        _ third: C.Type,
        reading r1: R1.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout A, inout B, inout C, QueryRow<R1>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(A.self, B.self, C.self, reads: [ObjectIdentifier(R1.self)], reader: { world in world.reader(R1.self) { QueryRow(entity: $0, components: $1) } }, filter: filter, body: body)
    }

    /// Changes three components of every entity that holds all three and the given read types,
    /// in place.
    ///
    /// See `update(_:_:_:reading:where:body:)` for how a visit proceeds.
    @inlinable
    public mutating func update<A: Component, B: Component, C: Component, R1: Component, R2: Component, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        _ third: C.Type,
        reading r1: R1.Type, _ r2: R2.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout A, inout B, inout C, QueryRow<R1, R2>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(A.self, B.self, C.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self)], reader: { world in world.reader(R1.self, R2.self) { QueryRow(entity: $0, components: ($1, $2)) } }, filter: filter, body: body)
    }

    /// Changes three components of every entity that holds all three and the given read types,
    /// in place.
    ///
    /// See `update(_:_:_:reading:where:body:)` for how a visit proceeds.
    @inlinable
    public mutating func update<A: Component, B: Component, C: Component, R1: Component, R2: Component, R3: Component, Failure: Error>(
        _ first: A.Type,
        _ second: B.Type,
        _ third: C.Type,
        reading r1: R1.Type, _ r2: R2.Type, _ r3: R3.Type,
        where filter: QueryFilter = QueryFilter(),
        body: (inout A, inout B, inout C, QueryRow<R1, R2, R3>) throws(Failure) -> Void
    ) throws(Failure) {
        try update(A.self, B.self, C.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self), ObjectIdentifier(R3.self)], reader: { world in world.reader(R1.self, R2.self, R3.self) { QueryRow(entity: $0, components: ($1, $2, $3)) } }, filter: filter, body: body)
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
        let reader = makeReader(self)
        let resolved = ResolvedFilter(filter, in: self, touching: reads + [ObjectIdentifier(W.self)], terms: reader.types + [ObjectIdentifier(W.self)])
        guard !resolved.isUnsatisfiable else { return }
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
        for candidate in resolved.candidates where candidate.count < driver.count {
            driver = candidate
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
        let reader = makeReader(self)
        let written = [ObjectIdentifier(A.self), ObjectIdentifier(B.self)]
        let resolved = ResolvedFilter(filter, in: self, touching: reads + written, terms: reader.types + written)
        guard !resolved.isUnsatisfiable else { return }
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
        for candidate in resolved.candidates where candidate.count < driver.count {
            driver = candidate
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
        let reader = makeReader(self)
        let resolved = ResolvedFilter(filter, in: self, touching: reads + written, terms: reader.types + written)
        guard !resolved.isUnsatisfiable else { return }
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
        for candidate in resolved.candidates where candidate.count < driver.count {
            driver = candidate
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
