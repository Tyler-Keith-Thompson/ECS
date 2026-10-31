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

/// The error ``World/group(checked:)`` throws: one case per way grouping can fail.
@frozen
public enum GroupError: Error, Hashable, Sendable {
    /// Fewer than two types, or one type listed twice.
    case tooFewTypes
    /// A type is already owned by another group.
    case alreadyOwned
}

extension World {
    // MARK: Groups

    /// Keeps `types` packed in the same order from now on, so queries and updates over exactly
    /// these types visit their entities with no lookups.
    ///
    /// The entities holding every one of `types` sit at the front of each type's storage, at the
    /// same positions; spawning, inserting, removing and despawning keep them there. A query of
    /// the same types in any order, or an update writing and reading exactly them, walks that
    /// front directly.
    ///
    /// ```swift
    /// world.group(Position.self, Velocity.self)
    /// world.update(Position.self, reading: Velocity.self) { position, row in … }  // no lookups
    /// ```
    ///
    /// Grouping changes the order queries list entities in, and makes adding and removing the
    /// owned types a little slower. A copy of the world keeps the group; a snapshot does not.
    ///
    /// - Complexity: O(*n*·*t*) for *n* entities in the smallest of the *t* types.
    /// - Precondition: At least two distinct types, none owned by another group. Use
    ///   ``group(checked:)`` to throw instead.
    @inlinable
    public mutating func group<each C: Component>(_ types: repeat (each C).Type) {
        do throws(GroupError) {
            try group(checked: repeat each types)
        } catch {
            preconditionFailure(error == .tooFewTypes ? "A group owns at least two distinct types" : "A type is already owned by another group")
        }
    }

    /// Keeps `types` packed in the same order from now on; see ``group(_:)``.
    ///
    /// - Complexity: O(*n*·*t*) for *n* entities in the smallest of the *t* types.
    /// - Throws: ``GroupError/tooFewTypes`` for fewer than two distinct types and
    ///   ``GroupError/alreadyOwned`` when a type is owned by another group; the world is unchanged.
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
