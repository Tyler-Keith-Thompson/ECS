/// One part of a ``Query``: which entities it matches and the value it yields for each.
///
/// Every ``Component`` is a term that matches the entities holding it and yields the component.
/// ``AnyOf`` is a term that matches entities holding at least one of its types.
public protocol QueryTerm: Sendable {
    /// What a query row holds for this term.
    associatedtype Value

    /// Reads this term from `world`; the general path a query of any shape takes.
    @_documentation(visibility: internal)
    static func _termReader(in world: World) -> TermReader<Value>

    /// `access`, also reading every component type this term reads.
    @_documentation(visibility: internal)
    static func _reading(_ access: Access) -> Access
}

/// How a query of any shape reads one term: the column it requires, if any, whether an entity
/// matches it, and its value.
@_documentation(visibility: internal)
@frozen
public struct TermReader<Value> {
    /// The type of the column every matched entity is in, or nil when the term requires none.
    @usableFromInline let required: ObjectIdentifier?
    /// The entities of that column.
    @usableFromInline let column: [Entity]
    /// Every type the term reads.
    @usableFromInline let reads: [ObjectIdentifier]
    /// Whether `entity` matches the term.
    @usableFromInline let matches: (_ entity: Entity) -> Bool
    /// The value of `entity`, which matches the term. A `cursor` other than -1 is the entity's
    /// position in `column`.
    @usableFromInline let value: (_ entity: Entity, _ cursor: Int) -> Value

    @inlinable
    init(
        required: ObjectIdentifier?, column: [Entity], reads: [ObjectIdentifier],
        matches: @escaping (Entity) -> Bool, value: @escaping (Entity, Int) -> Value
    ) {
        self.required = required
        self.column = column
        self.reads = reads
        self.matches = matches
        self.value = value
    }

    /// The value of `entity`, read at `cursor` when this term's column (`columns[term]`) is the
    /// one being walked. Counts `term` up by one, so a pack of readers can be read in one
    /// expansion.
    @inlinable
    func read(_ entity: Entity, cursor: Int, driver: Int, columns: [Int], term: inout Int) -> Value {
        defer { term += 1 }
        let column = columns[term]
        return value(entity, column >= 0 && (column == driver || driver == alignedDriver) ? cursor : -1)
    }
}

extension Component {
    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access {
        access.reads(Self.self)
    }

    @_documentation(visibility: internal)
    @inlinable
    public static func _termReader(in world: World) -> TermReader<Self> {
        let snapshot = world.snapshot(of: Self.self)
        return TermReader(
            required: ObjectIdentifier(Self.self), column: snapshot.index.dense, reads: [ObjectIdentifier(Self.self)],
            matches: { entity in snapshot.index.position(of: entity) != nil },
            value: { entity, cursor in snapshot.values[cursor >= 0 ? cursor : snapshot.index.position(of: entity)!] })
    }
}

/// A query term matching entities that hold at least one of its component types, yielding each
/// as an optional.
///
/// ```swift
/// let movers = Query(Position.self, AnyOf<Wind, Current>.self)
/// for (entity, position, (wind, current)) in world.query(movers) {
///     print(entity, position, wind ?? Wind(), current ?? Current())
/// }
/// ```
///
/// Queries of up to three terms, with `AnyOf` groups of two to four types, are specialized for
/// speed.
///
/// Among a query's filter types (``Query/Where``), `AnyOf` of filter types passes entities that
/// pass at least one: `AnyOf<Changed<Health>, Without<Shield>>`.
@frozen
public struct AnyOf<each C>: Sendable {}

extension AnyOf: QueryTerm where repeat each C: Component {
    /// One optional per type, in the order listed: nil where the entity lacks that type.
    public typealias Value = (repeat Optional<each C>)

    @_documentation(visibility: internal)
    @inlinable
    public static func _reading(_ access: Access) -> Access {
        var access = access
        for type in repeat (each C).self {
            access = type._reading(access)
        }
        return access
    }

    @_documentation(visibility: internal)
    @inlinable
    public static func _termReader(in world: World) -> TermReader<Value> {
        let snapshots = (repeat world.snapshot(of: (each C).self))
        var reads: [ObjectIdentifier] = []
        for type in repeat (each C).self {
            reads.append(ObjectIdentifier(type))
        }
        return TermReader(
            required: nil, column: [], reads: reads,
            matches: { entity in
                for snapshot in repeat each snapshots {
                    if snapshot.index.position(of: entity) != nil { return true }
                }
                return false
            },
            value: { entity, _ in
                (repeat (each snapshots).index.position(of: entity).map { (each snapshots).values[$0] })
            })
    }
}

extension World {
    /// Reads any number of terms, making each row with `make`: the general path of a query of
    /// any shape.
    @inlinable
    func termReader<each T: QueryTerm, Row>(
        _ terms: repeat (each T).Type, make: @escaping (Entity, (repeat (each T).Value)) -> Row
    ) -> Reader<Row> {
        let readers = (repeat (each T)._termReader(in: self))
        var types: [ObjectIdentifier] = []
        var columns: [[Entity]] = []
        // The read column of each term, -1 for a term that requires none.
        var columnOfTerm: [Int] = []
        for reader in repeat each readers {
            if let required = reader.required {
                columnOfTerm.append(columns.count)
                types.append(required)
                columns.append(reader.column)
            } else {
                columnOfTerm.append(-1)
            }
        }
        // Constant, so the row closure captures it unboxed.
        let termColumns = columnOfTerm
        return Reader(types: types, columns: columns) { entity, cursor, driver in
            var term = 0
            for reader in repeat each readers {
                let column = termColumns[term]
                term += 1
                if column >= 0, column == driver || driver == alignedDriver { continue }
                if !reader.matches(entity) { return nil }
            }
            term = 0
            return make(entity, (repeat (each readers).read(entity, cursor: cursor, driver: driver, columns: termColumns, term: &term)))
        }
    }

    /// Every type read by `terms`, for the check that an update reads none it writes.
    @inlinable
    func termReads<each T: QueryTerm>(_ terms: repeat (each T).Type) -> [ObjectIdentifier] {
        var reads: [ObjectIdentifier] = []
        for reader in repeat (each T)._termReader(in: self) {
            reads += reader.reads
        }
        return reads
    }
}
