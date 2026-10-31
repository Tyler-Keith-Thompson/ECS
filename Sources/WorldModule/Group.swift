/// Component types a world keeps packed in the same order: the entities holding all of them sit
/// at the front of each type's storage, at the same positions.
@usableFromInline
struct OwningGroup: Sendable {
    /// The owned types.
    @usableFromInline let types: Set<ObjectIdentifier>
    /// The slots of the owned types' columns.
    @usableFromInline let slots: [Int]
    /// The number of entities holding every owned type.
    @usableFromInline var count = 0

    @inlinable
    init(types: Set<ObjectIdentifier>, slots: [Int]) {
        self.types = types
        self.slots = slots
    }
}

/// An error that grouping component types throws.
///
/// ``World/group(checked:)`` throws this error, with one case per way grouping can fail, and
/// leaves the world unchanged.
@frozen
public enum GroupError: Error, Hashable, Sendable {
    /// The group lists fewer than two types, or lists a type twice.
    case tooFewTypes
    /// Another group already owns one of the types.
    case alreadyOwned
}

extension World {
    // MARK: Groups

    /// Keeps the given component types packed in the same order, so that queries and updates of
    /// exactly these types visit their entities without lookups.
    ///
    /// A query of several types normally walks one type's storage and looks up the entity in each
    /// of the others. After you group the types, the entities that hold all of them sit at the
    /// front of each type's storage, at the same positions, and spawning, inserting, removing and
    /// despawning keep them there. A query of the same types in any order, or an update that
    /// writes and reads exactly those types, walks that front directly.
    ///
    /// Use a group for a set of types you visit together on every step, such as position and
    /// velocity:
    ///
    /// ```swift
    /// var world = World()
    /// let comet = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
    /// world.spawn(Position(x: 9, y: 9))
    /// world.group(Position.self, Velocity.self)
    ///
    /// world.update(Position.self, reading: Velocity.self) { position, row in
    ///     position.x += row.components.dx
    ///     position.y += row.components.dy
    /// }
    /// print(world[Position.self, of: comet])
    /// // Prints "Position(x: 1.0, y: 2.0)"
    /// ```
    ///
    /// Grouping doesn't change which entities a query or update visits, only how it finds them.
    /// It does change the order queries list entities in, and makes adding and removing the
    /// grouped types a little slower. Each type belongs to at most one group. A copy of the world
    /// keeps the group; a snapshot doesn't.
    ///
    /// - Parameter types: The component types to keep packed together.
    /// - Complexity: O(*n*·*t*) for *n* entities in the smallest of the *t* types.
    /// - Precondition: `types` lists at least two distinct types, and no other group owns any of
    ///   them. The checked spelling, ``group(checked:)``, throws instead.
    @inlinable
    public mutating func group<each C: Component>(_ types: repeat (each C).Type) {
        do throws(GroupError) {
            try group(checked: repeat each types)
        } catch {
            preconditionFailure(error == .tooFewTypes ? "A group owns at least two distinct types" : "A type is already owned by another group")
        }
    }

    /// Keeps the given component types packed in the same order, throwing an error if they can't
    /// be grouped.
    ///
    /// This method groups the types as ``group(_:)`` does, but throws where that method traps:
    ///
    /// ```swift
    /// var world = World()
    /// try world.group(checked: Position.self, Velocity.self)
    ///
    /// do {
    ///     try world.group(checked: Velocity.self, Health.self)
    /// } catch {
    ///     print(error)
    ///     // Prints "alreadyOwned"
    /// }
    /// ```
    ///
    /// - Parameter types: The component types to keep packed together.
    /// - Complexity: O(*n*·*t*) for *n* entities in the smallest of the *t* types.
    /// - Throws: ``GroupError/tooFewTypes`` if `types` lists fewer than two distinct types, and
    ///   ``GroupError/alreadyOwned`` if another group owns one of them. The world is unchanged.
    @inlinable
    public mutating func group<each C: Component>(checked types: repeat (each C).Type) throws(GroupError) {
        var identifiers: [ObjectIdentifier] = []
        for type in repeat each types {
            identifiers.append(ObjectIdentifier(type))
        }
        guard identifiers.count >= 2, Set(identifiers).count == identifiers.count else { throw .tooFewTypes }
        for identifier in identifiers {
            if let slot = columnPositions.position(of: identifier), columns[slot].group >= 0 { throw .alreadyOwned }
        }
        var slots: [Int] = []
        for type in repeat each types {
            let slot = columnSlot(of: type)
            _ = uniqueColumn(at: slot, of: type)
            slots.append(slot)
        }
        let group = groups.count
        groups.append(OwningGroup(types: Set(identifiers), slots: slots))
        for slot in slots {
            columns[slot].group = group
        }
        let smallest = slots.min { columns[$0].index.dense.count < columns[$1].index.dense.count }!
        for entity in columns[smallest].index.dense {
            joinGroup(group, entity)
        }
    }

    /// The number of entities at the front of every column of `types` when an owning group owns
    /// exactly `types`, or nil.
    @inlinable
    func alignedCount(of types: [ObjectIdentifier]) -> Int? {
        guard !groups.isEmpty else { return nil }
        for group in groups where group.types.count == types.count && types.allSatisfy(group.types.contains) {
            return group.count
        }
        return nil
    }

    /// Moves `entity` into group `group` if it holds every owned type and is not in it.
    @usableFromInline
    @inline(never)
    mutating func joinGroup(_ group: Int, _ entity: Entity) {
        let count = groups[group].count
        var positions: [Int] = []
        for slot in groups[group].slots {
            guard let position = columns[slot].index.position(of: entity), position >= count else { return }
            positions.append(position)
        }
        for (slot, position) in zip(groups[group].slots, positions) {
            uniqueSwap(at: slot, position, count)
        }
        groups[group].count += 1
    }

    /// Moves `entity` out of group `group` if it is in it.
    @usableFromInline
    @inline(never)
    mutating func leaveGroup(_ group: Int, _ entity: Entity) {
        let count = groups[group].count
        guard let position = columns[groups[group].slots[0]].index.position(of: entity), position < count else { return }
        for slot in groups[group].slots {
            uniqueSwap(at: slot, position, count - 1)
        }
        groups[group].count -= 1
    }

    /// Moves `entity` out of every group it is in, before it is despawned.
    @usableFromInline
    @inline(never)
    mutating func leaveGroups(_ entity: Entity) {
        for group in groups.indices {
            leaveGroup(group, entity)
        }
    }

    /// Swaps two positions of the column at `slot`, copying it first if it is shared.
    @usableFromInline
    mutating func uniqueSwap(at slot: Int, _ first: Int, _ second: Int) {
        guard first != second else { return }
        if !isKnownUniquelyReferenced(&columns[slot]) {
            copyColumn(at: slot)
        }
        let column = columns[slot]
        column.swapAt(column, first, second)
    }
}
