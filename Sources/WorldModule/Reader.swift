/// How a query or an update reads its component types: their columns' entities, for choosing
/// which column to walk, and a closure that reads one entity's row.
///
/// The closure is written for each number of types up to three, where the compiler specializes it
/// fully, and once over a parameter pack for any number. Choosing among them in the fixed-arity
/// overloads of ``World/query(_:)`` and ``World/update(_:reading:where:body:)`` keeps the
/// per-entity work free of pack expansion.
@frozen
@usableFromInline
struct Reader<each R: Component> {
    /// The entities of each read column, in the order the types were listed.
    @usableFromInline let columns: [[Entity]]
    /// The row of `entity`, or nil if it lacks a read type. When `entity` was found at `cursor`
    /// in read column `driver` (pass -1 for none), that column is read at `cursor` directly.
    @usableFromInline let row: (_ entity: Entity, _ cursor: Int, _ driver: Int) -> QueryRow<repeat each R>?

    @inlinable
    init(columns: [[Entity]], row: @escaping (Entity, Int, Int) -> QueryRow<repeat each R>?) {
        self.columns = columns
        self.row = row
    }
}

extension World {
    /// Reads any number of types.
    @inlinable
    func packReader<each R: Component>(_ types: repeat (each R).Type) -> Reader<repeat each R> {
        let snapshots = (repeat snapshot(of: (each R).self))
        var columns: [[Entity]] = []
        for snapshot in repeat each snapshots {
            columns.append(snapshot.index.dense)
        }
        return Reader(columns: columns) { entity, cursor, driver in
            var column = 0
            for snapshot in repeat each snapshots {
                if column != driver, snapshot.index.position(of: entity) == nil { return nil }
                column += 1
            }
            column = 0
            return QueryRow(entity: entity, components: (repeat (each snapshots).value(
                of: entity, cursor: cursor, driverColumn: driver, column: &column)))
        }
    }

    /// Reads one type.
    @inlinable
    func reader<A: Component>(_ a: A.Type) -> Reader<A> {
        let a = snapshot(of: A.self)
        return Reader(columns: [a.index.dense]) { entity, cursor, driver in
            let first: Int
            if driver == 0 { first = cursor } else {
                guard let found = a.index.position(of: entity) else { return nil }
                first = found
            }
            return QueryRow(entity: entity, components: a.values[first])
        }
    }

    /// Reads two types.
    @inlinable
    func reader<A: Component, B: Component>(_ a: A.Type, _ b: B.Type) -> Reader<A, B> {
        let a = snapshot(of: A.self)
        let b = snapshot(of: B.self)
        return Reader(columns: [a.index.dense, b.index.dense]) { entity, cursor, driver in
            let first: Int
            let second: Int
            if driver == 0 { first = cursor } else {
                guard let found = a.index.position(of: entity) else { return nil }
                first = found
            }
            if driver == 1 { second = cursor } else {
                guard let found = b.index.position(of: entity) else { return nil }
                second = found
            }
            return QueryRow(entity: entity, components: (a.values[first], b.values[second]))
        }
    }

    /// Reads three types.
    @inlinable
    func reader<A: Component, B: Component, C: Component>(_ a: A.Type, _ b: B.Type, _ c: C.Type) -> Reader<A, B, C> {
        let a = snapshot(of: A.self)
        let b = snapshot(of: B.self)
        let c = snapshot(of: C.self)
        return Reader(columns: [a.index.dense, b.index.dense, c.index.dense]) { entity, cursor, driver in
            let first: Int
            let second: Int
            let third: Int
            if driver == 0 { first = cursor } else {
                guard let found = a.index.position(of: entity) else { return nil }
                first = found
            }
            if driver == 1 { second = cursor } else {
                guard let found = b.index.position(of: entity) else { return nil }
                second = found
            }
            if driver == 2 { third = cursor } else {
                guard let found = c.index.position(of: entity) else { return nil }
                third = found
            }
            return QueryRow(entity: entity, components: (a.values[first], b.values[second], c.values[third]))
        }
    }
}
