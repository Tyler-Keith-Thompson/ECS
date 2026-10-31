/// A type that can be a term of a query, deciding which entities match and what the query reads
/// from each.
///
/// Every ``Component`` is a query term: it matches the entities that hold the component and reads
/// the component's value. ``AnyOf`` is a query term that matches the entities holding at least one
/// of its component types and reads each as an optional.
///
/// You don't conform types to this protocol yourself; declare components and use ``AnyOf``.
public protocol QueryTerm: Sendable {
    /// The value a query's row holds for this term.
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

/// A group of types an entity matches by matching at least one of them.
///
/// As a term of a ``Query``, `AnyOf` of component types matches the entities that hold at least
/// one of the types, and reads a tuple with one optional per type: the entity's component, or
/// `nil` where the entity lacks that type. Use it to visit entities that may carry any of several
/// related components:
///
/// ```swift
/// var world = World()
/// world.spawn(Name(value: "frozen comet"), Velocity(dx: 4, dy: 0), Frozen())
/// world.spawn(Name(value: "comet"), Velocity(dx: 2, dy: 0))
/// world.spawn(Name(value: "ice"), Frozen())
/// world.spawn(Name(value: "rock"))
///
/// var descriptions: [String] = []
/// for (_, name, (velocity, frozen)) in world.query(Query(Name.self, AnyOf<Velocity, Frozen>.self)) {
///     let state = frozen == nil ? "moving at \(velocity?.dx ?? 0)" : "frozen"
///     descriptions.append("\(name.value) is \(state)")
/// }
/// print(descriptions)
/// // Prints "["frozen comet is frozen", "comet is moving at 2.0", "ice is frozen"]"
/// ```
///
/// The rock holds neither type, so the query skips it.
///
/// As a filter type of a system's query (``Query/Where``), `AnyOf` of filter types passes the
/// entities that pass at least one of them: `Query<Health>.Where<AnyOf<Changed<Health>,
/// Without<Frozen>>>` visits the entities whose health changed and the ones that aren't frozen.
///
/// Queries of one to three terms, with `AnyOf` groups of two to four types, run through code
/// specialized for their exact shape.
@frozen
public struct AnyOf<each C>: Sendable {}

extension AnyOf: QueryTerm where repeat each C: Component {
    /// A tuple of one optional per component type, in the order listed, with `nil` where the
    /// entity lacks that type.
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
