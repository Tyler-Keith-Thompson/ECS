/// A world's entities, hierarchy and components of the types `C`, as a `Codable` value.
///
/// Take one with ``World/snapshot(_:)`` and rebuild a world from it with
/// ``World/init(restoring:)``. Every entity handle, live or stale, means the same in the restored
/// world, and the restored world hands out the same handles from later spawns.
///
/// ```swift
/// let data = try JSONEncoder().encode(world.snapshot(Position.self, Velocity.self))
/// let snapshot = try JSONDecoder().decode(WorldSnapshot<Position, Velocity>.self, from: data)
/// let restored = World(restoring: snapshot)
/// ```
///
/// A snapshot holds no resources, hooks or change ticks: the restored world's components are all
/// added at its first tick. Decoding throws `DecodingError.dataCorrupted` for data no world could
/// have produced.
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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: WorldSnapshotCodingKeys.self)
        let generations = try container.decode([UInt32].self, forKey: .generations)
        let vacant = try container.decode([UInt32].self, forKey: .vacant)
        let families = try container.decode([Family].self, forKey: .families)
        var components = try container.nestedUnkeyedContainer(forKey: .components)
        let columns = (repeat try components.decode(ComponentRows<each C>.self))
        func corrupted(_ description: String) -> DecodingError {
            .dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: description))
        }
        guard generations.count < Int(UInt32.max) else { throw corrupted("Too many slots") }
        var isLive = [Bool](repeating: true, count: generations.count)
        for slot in vacant {
            guard Int(slot) < generations.count, isLive[Int(slot)] else { throw corrupted("Invalid vacant slot \(slot)") }
            isLive[Int(slot)] = false
        }
        func isLiveEntity(_ entity: Entity) -> Bool {
            Int(entity.index) < generations.count && isLive[Int(entity.index)] && generations[Int(entity.index)] == entity.generation
        }
        for column in repeat each columns {
            guard column.entities.count == column.values.count else { throw corrupted("Mismatched component rows") }
            var seen = Set<Entity>()
            for entity in column.entities {
                guard isLiveEntity(entity), seen.insert(entity).inserted else {
                    throw corrupted("Invalid or repeated entity \(entity) in a component column")
                }
            }
        }
        var parentOf: [Entity: Entity] = [:]
        for family in families {
            guard isLiveEntity(family.parent) else { throw corrupted("Invalid parent \(family.parent)") }
            for child in family.children {
                guard isLiveEntity(child), parentOf.updateValue(family.parent, forKey: child) == nil else {
                    throw corrupted("Invalid or repeated child \(child)")
                }
            }
        }
        for start in parentOf.keys {
            var steps = 0
            var current = parentOf[start]
            while let walking = current {
                steps += 1
                guard walking != start, steps <= parentOf.count else { throw corrupted("Cyclic hierarchy") }
                current = parentOf[walking]
            }
        }
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
    /// The world's entities, hierarchy and components of the types `C`.
    ///
    /// Components of other types are left out.
    ///
    /// - Complexity: O(*n*) for *n* entities and components saved.
    @inlinable
    public func snapshot<each C: Component & Codable>(_ types: repeat (each C).Type) -> WorldSnapshot<repeat each C> {
        var families: [Family] = []
        for slot in hierarchy.children.indices where !hierarchy.children[slot].isEmpty {
            families.append(Family(parent: Entity(index: UInt32(slot), generation: generations[slot]), children: hierarchy.children[slot]))
        }
        return WorldSnapshot(
            generations: generations,
            vacant: vacant,
            families: families,
            columns: (repeat rows(of: each types))
        )
    }

    @inlinable
    func rows<C: Component & Codable>(of type: C.Type) -> ComponentRows<C> {
        guard let column = column(of: C.self) else { return ComponentRows(entities: [], values: []) }
        return ComponentRows(entities: column.index.dense, values: column.values)
    }

    /// The world `snapshot` was taken of, with its entities, hierarchy and the components it
    /// saved.
    ///
    /// - Complexity: O(*n*) for *n* entities and components restored.
    @inlinable
    public init<each C: Component & Codable>(restoring snapshot: WorldSnapshot<repeat each C>) {
        self.init()
        generations = snapshot.generations
        vacant = snapshot.vacant
        isLive = [Bool](repeating: true, count: generations.count)
        for slot in vacant {
            isLive[Int(slot)] = false
        }
        for family in snapshot.families {
            for child in family.children {
                hierarchy.link(child, to: family.parent)
            }
        }
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
    /// Whether the two snapshots hold the same entities, hierarchy and components, whatever
    /// order the worlds stored their components in.
    ///
    /// Comparing the snapshots of two worlds compares the worlds:
    ///
    /// ```swift
    /// #expect(replayed.snapshot(Position.self, Health.self) == recorded.snapshot(Position.self, Health.self))
    /// ```
    ///
    /// Slots, generations and the order of vacated slots must match, so equal worlds also hand
    /// out the same handles from later spawns, and children must be in the same order.
    ///
    /// - Complexity: O(*n* log *n*) for *n* entities and components.
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
