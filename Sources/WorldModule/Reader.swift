/// The driver of a visit over an owning group's entities: every column holds the entity at the
/// cursor.
@usableFromInline
let alignedDriver = Int.max

/// How a query or an update reads its component types: their columns' entities, for choosing
/// which column to walk, and a closure that reads one entity's row.
///
/// The closure is written for each number of types up to three, where the compiler specializes it
/// fully, and once over a parameter pack for any number. Choosing among them in the fixed-arity
/// overloads of `World.query(_:)` and `World.update(_:reading:where:body:)` keeps the
/// per-entity work free of pack expansion. `Row` is what a visit receives: a tuple for a query, a
/// ``QueryRow`` for an update.
@frozen
@usableFromInline
struct Reader<Row> {
    /// The types every matched entity holds, in the order they were listed: the types of the
    /// read columns.
    @usableFromInline let types: [ObjectIdentifier]
    /// Every type the rows read, `types` and the members of ``AnyOf`` terms, so a visit doesn't
    /// skip the entities holding a disabling component it reads.
    @usableFromInline let reads: [ObjectIdentifier]
    /// The entities of each read column, in the order the types were listed.
    @usableFromInline let columns: [[Entity]]
    /// The row of `entity`, or nil if it lacks a read type. When `entity` was found at `cursor`
    /// in read column `driver` (pass -1 for none), that column is read at `cursor` directly;
    /// with `alignedDriver`, every column is.
    @usableFromInline let row: (_ entity: Entity, _ cursor: Int, _ driver: Int) -> Row?

    @inlinable
    init(types: [ObjectIdentifier], reads: [ObjectIdentifier]? = nil, columns: [[Entity]], row: @escaping (Entity, Int, Int) -> Row?) {
        self.types = types
        self.reads = reads ?? types
        self.columns = columns
        self.row = row
    }
}

extension World {
    /// Reads any number of types, making each row with `make`.
    @inlinable
    func packReader<each R: Component, Row>(
        _ types: repeat (each R).Type, make: @escaping (Entity, (repeat each R)) -> Row
    ) -> Reader<Row> {
        let snapshots = (repeat snapshot(of: (each R).self))
        var columns: [[Entity]] = []
        for snapshot in repeat each snapshots {
            columns.append(snapshot.index.dense)
        }
        var types: [ObjectIdentifier] = []
        for type in repeat (each R).self {
            types.append(ObjectIdentifier(type))
        }
        return Reader(types: types, columns: columns) { entity, cursor, driver in
            var column = 0
            for snapshot in repeat each snapshots {
                if column != driver, driver != alignedDriver, snapshot.index.position(of: entity) == nil { return nil }
                column += 1
            }
            column = 0
            return make(entity, (repeat (each snapshots).value(
                of: entity, cursor: cursor, driverColumn: driver, column: &column)))
        }
    }

    /// Reads one type, making each row with `make`.
    @inlinable
    func reader<A: Component, Row>(_ a: A.Type, make: @escaping (Entity, A) -> Row) -> Reader<Row> {
        let a = snapshot(of: A.self)
        return Reader(types: [ObjectIdentifier(A.self)], columns: [a.index.dense]) { entity, cursor, driver in
            let first: Int
            if driver == 0 || driver == alignedDriver { first = cursor } else {
                guard let found = a.index.position(of: entity) else { return nil }
                first = found
            }
            return make(entity, a.values[first])
        }
    }

    /// Reads two types, making each row with `make`.
    @inlinable
    func reader<A: Component, B: Component, Row>(
        _ a: A.Type, _ b: B.Type, make: @escaping (Entity, A, B) -> Row
    ) -> Reader<Row> {
        let a = snapshot(of: A.self)
        let b = snapshot(of: B.self)
        return Reader(types: [ObjectIdentifier(A.self), ObjectIdentifier(B.self)], columns: [a.index.dense, b.index.dense]) { entity, cursor, driver in
            let first: Int
            let second: Int
            if driver == 0 || driver == alignedDriver { first = cursor } else {
                guard let found = a.index.position(of: entity) else { return nil }
                first = found
            }
            if driver == 1 || driver == alignedDriver { second = cursor } else {
                guard let found = b.index.position(of: entity) else { return nil }
                second = found
            }
            return make(entity, a.values[first], b.values[second])
        }
    }

    /// Reads three types, making each row with `make`.
    @inlinable
    func reader<A: Component, B: Component, C: Component, Row>(
        _ a: A.Type, _ b: B.Type, _ c: C.Type, make: @escaping (Entity, A, B, C) -> Row
    ) -> Reader<Row> {
        let a = snapshot(of: A.self)
        let b = snapshot(of: B.self)
        let c = snapshot(of: C.self)
        return Reader(types: [ObjectIdentifier(A.self), ObjectIdentifier(B.self), ObjectIdentifier(C.self)], columns: [a.index.dense, b.index.dense, c.index.dense]) { entity, cursor, driver in
            let first: Int
            let second: Int
            let third: Int
            if driver == 0 || driver == alignedDriver { first = cursor } else {
                guard let found = a.index.position(of: entity) else { return nil }
                first = found
            }
            if driver == 1 || driver == alignedDriver { second = cursor } else {
                guard let found = b.index.position(of: entity) else { return nil }
                second = found
            }
            if driver == 2 || driver == alignedDriver { third = cursor } else {
                guard let found = c.index.position(of: entity) else { return nil }
                third = found
            }
            return make(entity, a.values[first], b.values[second], c.values[third])
        }
    }
}
