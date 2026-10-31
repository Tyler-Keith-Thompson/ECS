import Dispatch

extension World {
    /// Changes the `W` of every entity that holds one, every type in `reading` and passes
    /// `filter`, in place, spreading the entities across the processor's cores.
    ///
    /// The result is the same as ``update(_:reading:where:body:)``'s: `body` can change only
    /// the `W` it is given, and being `@Sendable` it shares no mutable state between entities,
    /// so the order entities are visited in cannot change the outcome. Updates over fewer than
    /// `minimumChunk` entities run on the calling thread.
    ///
    /// ```swift
    /// world.parallelUpdate(Position.self, reading: Velocity.self) { position, row in
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
    ///   - minimumChunk: The fewest entities one core is given.
    ///   - body: Changes one entity's `W`.
    /// - Complexity: O(*n* / *p*) for *n* entities in the smallest of the types on *p* cores,
    ///   plus a copy of the `W` storage when another world shares it.
    /// - Precondition: `reading` does not list `W`, and `minimumChunk` is positive.
    @inlinable
    public mutating func parallelUpdate<W: Component, each R: Component>(
        _ type: W.Type,
        reading: repeat (each R).Type,
        where filter: QueryFilter = QueryFilter(),
        minimumChunk: Int = 4096,
        body: @escaping @Sendable (inout W, QueryRow<repeat each R>) -> Void
    ) {
        var reads: [ObjectIdentifier] = []
        for read in repeat (each R).self {
            reads.append(ObjectIdentifier(read))
        }
        parallelUpdate(W.self, reads: reads, reader: { world in world.packReader(repeat (each R).self) { entity, components in QueryRow(entity: entity, components: (repeat each components)) } }, filter: filter, minimumChunk: minimumChunk, body: body)
    }

    /// Changes the `W` of every entity holding one and the read type across cores; see
    /// ``parallelUpdate(_:reading:where:minimumChunk:body:)``.
    @inlinable
    public mutating func parallelUpdate<W: Component, R1: Component>(
        _ type: W.Type,
        reading r1: R1.Type,
        where filter: QueryFilter = QueryFilter(),
        minimumChunk: Int = 4096,
        body: @escaping @Sendable (inout W, QueryRow<R1>) -> Void
    ) {
        parallelUpdate(W.self, reads: [ObjectIdentifier(R1.self)], reader: { world in world.reader(R1.self) { QueryRow(entity: $0, components: $1) } }, filter: filter, minimumChunk: minimumChunk, body: body)
    }

    /// Changes the `W` of every entity holding one and the read types across cores; see
    /// ``parallelUpdate(_:reading:where:minimumChunk:body:)``.
    @inlinable
    public mutating func parallelUpdate<W: Component, R1: Component, R2: Component>(
        _ type: W.Type,
        reading r1: R1.Type, _ r2: R2.Type,
        where filter: QueryFilter = QueryFilter(),
        minimumChunk: Int = 4096,
        body: @escaping @Sendable (inout W, QueryRow<R1, R2>) -> Void
    ) {
        parallelUpdate(W.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self)], reader: { world in world.reader(R1.self, R2.self) { QueryRow(entity: $0, components: ($1, $2)) } }, filter: filter, minimumChunk: minimumChunk, body: body)
    }

    /// Changes the `W` of every entity holding one and the read types across cores; see
    /// ``parallelUpdate(_:reading:where:minimumChunk:body:)``.
    @inlinable
    public mutating func parallelUpdate<W: Component, R1: Component, R2: Component, R3: Component>(
        _ type: W.Type,
        reading r1: R1.Type, _ r2: R2.Type, _ r3: R3.Type,
        where filter: QueryFilter = QueryFilter(),
        minimumChunk: Int = 4096,
        body: @escaping @Sendable (inout W, QueryRow<R1, R2, R3>) -> Void
    ) {
        parallelUpdate(W.self, reads: [ObjectIdentifier(R1.self), ObjectIdentifier(R2.self), ObjectIdentifier(R3.self)], reader: { world in world.reader(R1.self, R2.self, R3.self) { QueryRow(entity: $0, components: ($1, $2, $3)) } }, filter: filter, minimumChunk: minimumChunk, body: body)
    }

    /// Visits every entity holding a `W`, the read types and passing `filter` across cores,
    /// changing its `W`.
    @inlinable
    mutating func parallelUpdate<W: Component, each R: Component>(
        _ type: W.Type,
        reads: [ObjectIdentifier],
        reader makeReader: (World) -> Reader<QueryRow<repeat each R>>,
        filter: QueryFilter,
        minimumChunk: Int,
        body: @escaping @Sendable (inout W, QueryRow<repeat each R>) -> Void
    ) {
        precondition(!reads.contains(ObjectIdentifier(W.self)), "parallelUpdate reads the \(W.self) it writes")
        precondition(minimumChunk > 0, "parallelUpdate needs a positive minimum chunk")
        guard let slot = columnPositions.position(of: ObjectIdentifier(W.self)) else { return }
        let reader = makeReader(self)
        let resolved = ResolvedFilter(filter, in: self, touching: reads + [ObjectIdentifier(W.self)], terms: reader.types + [ObjectIdentifier(W.self)])
        guard !resolved.isUnsatisfiable else { return }
        let column = uniqueColumn(at: slot, of: W.self)
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
        var visitedCount = driver.count
        if let aligned = alignedCount(of: [ObjectIdentifier(W.self)] + reads) {
            driver = index.dense
            driverColumn = alignedDriver
            visitedCount = aligned
        }
        let entityCount = visitedCount
        let checksFilter = !resolved.isEmpty
        let chunkCount = max(1, entityCount / minimumChunk)
        let chunkSize = (entityCount + chunkCount - 1) / chunkCount

        ticks.withUnsafeMutableBufferPointer { ticks in
            values.withUnsafeMutableBufferPointer { values in
                // Each entity appears once in the driver, so chunks write disjoint positions.
                let visit = ParallelVisit(
                    driver: driver, driverColumn: driverColumn, index: index, resolved: resolved,
                    checksFilter: checksFilter, reader: reader, tick: tick, ticks: ticks, values: values, body: body
                )
                if chunkCount == 1 {
                    visit.run(0 ..< entityCount)
                } else {
                    DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
                        let start = min(chunk * chunkSize, entityCount)
                        visit.run(start ..< min(start + chunkSize, entityCount))
                    }
                }
            }
        }
    }
}

/// One parallel update's read-only state and its write buffers, shared by the chunks that
/// visit disjoint ranges of the driver.
///
/// Unchecked: the reader's closures and the filter only read storage that no one writes during
/// the visit, and each position of the buffers is written by one chunk.
@usableFromInline
struct ParallelVisit<W: Component, Row>: @unchecked Sendable {
    @usableFromInline let driver: [Entity]
    @usableFromInline let driverColumn: Int
    @usableFromInline let index: SparseIndex
    @usableFromInline let resolved: ResolvedFilter
    @usableFromInline let checksFilter: Bool
    @usableFromInline let reader: Reader<Row>
    @usableFromInline let tick: ChangeTick
    @usableFromInline let ticks: UnsafeMutableBufferPointer<ComponentTicks>
    @usableFromInline let values: UnsafeMutableBufferPointer<W>
    @usableFromInline let body: @Sendable (inout W, Row) -> Void

    @inlinable
    init(
        driver: [Entity], driverColumn: Int, index: SparseIndex, resolved: ResolvedFilter, checksFilter: Bool,
        reader: Reader<Row>, tick: ChangeTick, ticks: UnsafeMutableBufferPointer<ComponentTicks>,
        values: UnsafeMutableBufferPointer<W>, body: @escaping @Sendable (inout W, Row) -> Void
    ) {
        self.driver = driver
        self.driverColumn = driverColumn
        self.index = index
        self.resolved = resolved
        self.checksFilter = checksFilter
        self.reader = reader
        self.tick = tick
        self.ticks = ticks
        self.values = values
        self.body = body
    }

    /// Visits the driver's entities at `cursors`.
    @inlinable
    func run(_ cursors: Range<Int>) {
        for cursor in cursors {
            let entity = driver[cursor]
            var position = cursor
            if driverColumn != -2, driverColumn != alignedDriver {
                guard let found = index.position(of: entity) else { continue }
                position = found
            }
            if checksFilter, !resolved.passes(entity) { continue }
            guard let row = reader.row(entity, cursor, driverColumn) else { continue }
            ticks[position].changed = tick
            body(&values[position], row)
        }
    }
}
