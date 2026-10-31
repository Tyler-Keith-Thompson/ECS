/// A saved copy of a world's entities, hierarchy and the components of the listed types.
///
/// Use a snapshot to save a world and restore it later, or to compare two worlds. A snapshot
/// is `Codable`, so you can encode it with any encoder, such as `JSONEncoder`. Take one with
/// ``World/snapshot(_:)``, listing the component types to save, and rebuild a world from it
/// with `World(restoring:)`. Each component type you save must conform to `Codable`.
///
/// The following example saves a world as JSON and restores it:
///
/// ```swift
/// import Foundation
///
/// var world = World()
/// let ship = world.spawn(Position(x: 1, y: 2), Health(current: 3))
/// let data = try JSONEncoder().encode(world.snapshot(Position.self, Health.self))
///
/// let decoded = try JSONDecoder().decode(WorldSnapshot<Position, Health>.self, from: data)
/// let restored = World(restoring: decoded)
/// print(restored[Position.self, of: ship])
/// // Prints "Position(x: 1.0, y: 2.0)"
/// ```
///
/// Every entity handle, live or stale, means the same in the restored world as in the original,
/// so handles you saved elsewhere stay valid. The restored world also hands out the same handles
/// from later spawns.
///
/// A snapshot holds no resources, hooks or change ticks, and the restored world's components
/// are all added at its first tick. To save resources too, or to save a world without listing
/// its types at each call, use a ``Scene``.
///
/// - Note: Decoding throws `DecodingError.dataCorrupted` for data that no world could have
///   produced, such as a component of an entity that isn't live.
public struct WorldSnapshot<each C: Component & Codable>: Sendable, Codable {
    @usableFromInline let generations: [UInt32]
    @usableFromInline let vacant: [UInt32]
    /// Each parent with its children, in the order they were added.
    @usableFromInline let families: [Family]
    @usableFromInline let columns: (repeat ComponentRows<each C>)

    @inlinable
    init(generations: [UInt32], vacant: [UInt32], families: [Family], columns: (repeat ComponentRows<each C>)) {
        self.generations = generations
        self.vacant = vacant
        self.families = families
        self.columns = columns
    }

    /// The number of live entities.
    @inlinable
    public var count: Int { generations.count - vacant.count }

    /// Encodes the snapshot into the given encoder.
    ///
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: WorldSnapshotCodingKeys.self)
        try container.encode(generations, forKey: .generations)
        try container.encode(vacant, forKey: .vacant)
        try container.encode(families, forKey: .families)
        var components = container.nestedUnkeyedContainer(forKey: .components)
        for column in repeat each columns {
            try components.encode(column)
        }
    }

    /// Creates a snapshot by decoding from the given decoder.
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: `DecodingError.dataCorrupted` if the data describes a world that no world
    ///   could have produced, or any error the decoder throws.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: WorldSnapshotCodingKeys.self)
        let generations = try container.decode([UInt32].self, forKey: .generations)
        let vacant = try container.decode([UInt32].self, forKey: .vacant)
        let families = try container.decode([Family].self, forKey: .families)
        var components = try container.nestedUnkeyedContainer(forKey: .components)
        let columns = (repeat try components.decode(ComponentRows<each C>.self))
        var saved: [any SavedComponents] = []
        for column in repeat each columns {
            saved.append(column)
        }
        try validateLayout(generations: generations, vacant: vacant, families: families, columns: saved, codingPath: decoder.codingPath)
        self.init(generations: generations, vacant: vacant, families: families, columns: (repeat each columns))
    }
}

/// The keys of an encoded ``WorldSnapshot``.
@usableFromInline
enum WorldSnapshotCodingKeys: String, CodingKey {
    case generations, vacant, families, components
}

/// A parent and its children, in the order they were added.
@usableFromInline
struct Family: Sendable, Codable {
    @usableFromInline let parent: Entity
    @usableFromInline let children: [Entity]

    @inlinable
    init(parent: Entity, children: [Entity]) {
        self.parent = parent
        self.children = children
    }
}

/// The entities holding a `C` and their components, in the world's storage order.
@usableFromInline
struct ComponentRows<C: Component & Codable>: Sendable, Codable {
    @usableFromInline let entities: [Entity]
    @usableFromInline let values: [C]

    @inlinable
    init(entities: [Entity], values: [C]) {
        self.entities = entities
        self.values = values
    }
}

extension World {
    /// Returns a snapshot of the world's entities, hierarchy and the components of the given
    /// types.
    ///
    /// Components of other types are left out. See ``WorldSnapshot`` for an example.
    ///
    /// - Parameter types: The component types to save.
    /// - Returns: A snapshot of the world.
    /// - Complexity: O(*n*), where *n* is the number of entities and components saved.
    @inlinable
    public func snapshot<each C: Component & Codable>(_ types: repeat (each C).Type) -> WorldSnapshot<repeat each C> {
        return WorldSnapshot(
            generations: generations,
            vacant: vacant,
            families: families(),
            columns: (repeat rows(of: each types))
        )
    }

    @inlinable
    func rows<C: Component & Codable>(of type: C.Type) -> ComponentRows<C> {
        guard let column = column(of: C.self) else { return ComponentRows(entities: [], values: []) }
        return ComponentRows(entities: column.index.dense, values: column.values)
    }

    /// Creates a world from a snapshot, with the entities, hierarchy and components it saved.
    ///
    /// Every entity handle means the same in the new world as in the world the snapshot was
    /// taken of. See ``WorldSnapshot`` for an example.
    ///
    /// - Parameter snapshot: The snapshot to restore.
    /// - Complexity: O(*n*), where *n* is the number of entities and components restored.
    @inlinable
    public init<each C: Component & Codable>(restoring snapshot: WorldSnapshot<repeat each C>) {
        self.init(slots: snapshot.generations, vacant: snapshot.vacant, families: snapshot.families)
        for column in repeat each snapshot.columns {
            restore(column)
        }
    }

    @inlinable
    mutating func restore<C: Component & Codable>(_ rows: ComponentRows<C>) {
        for (entity, value) in zip(rows.entities, rows.values) {
            store(value, for: entity)
        }
    }
}

extension WorldSnapshot: Equatable where repeat each C: Equatable {
    /// Returns a Boolean value indicating whether two snapshots hold the same entities,
    /// hierarchy and components.
    ///
    /// Use this operator to compare two worlds, such as a world replayed from recorded input
    /// and the world that was recorded. The order a world stored its components in doesn't
    /// matter:
    ///
    /// ```swift
    /// var recorded = World()
    /// let first = recorded.spawn(Position(x: 0, y: 0))
    /// recorded.spawn(Position(x: 5, y: 5))
    ///
    /// var replayed = recorded
    /// replayed.remove(Position.self, from: first)
    /// replayed.insert(Position(x: 0, y: 0), into: first)
    ///
    /// print(replayed.snapshot(Position.self) == recorded.snapshot(Position.self))
    /// // Prints "true"
    /// ```
    ///
    /// Two snapshots are equal only if their slots, generations and order of vacated slots
    /// match, so equal worlds also hand out the same handles from later spawns. Children must be
    /// in the same order.
    ///
    /// - Parameters:
    ///   - lhs: A snapshot to compare.
    ///   - rhs: Another snapshot to compare.
    /// - Complexity: O(*n* log *n*), where *n* is the number of entities and components.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.generations == rhs.generations, lhs.vacant == rhs.vacant,
              lhs.families.sorted(by: { $0.parent < $1.parent }) == rhs.families.sorted(by: { $0.parent < $1.parent })
        else { return false }
        for (left, right) in repeat (each lhs.columns, each rhs.columns) {
            guard left.hasSameRows(as: right) else { return false }
        }
        return true
    }
}

extension Family: Equatable {}

extension ComponentRows where C: Equatable {
    /// Whether both hold the same entities with equal components, in any order.
    @usableFromInline
    func hasSameRows(as other: ComponentRows<C>) -> Bool {
        guard entities.count == other.entities.count else { return false }
        let order = entities.indices.sorted { entities[$0] < entities[$1] }
        let otherOrder = other.entities.indices.sorted { other.entities[$0] < other.entities[$1] }
        return zip(order, otherOrder).allSatisfy { position, otherPosition in
            entities[position] == other.entities[otherPosition] && values[position] == other.values[otherPosition]
        }
    }
}
