/// The entities holding each value of a `Hashable` component type, as of a version of its
/// column.
@usableFromInline
struct ValueIndex<C: Component & Hashable>: Sendable {
    @usableFromInline var entitiesByValue: [C: [Entity]] = [:]
    @usableFromInline var valueByEntity: [Entity: C] = [:]
    /// The column's write version the index agrees with.
    @usableFromInline var version: UInt64 = 0

    @inlinable
    init() {}

    @inlinable
    mutating func set(_ value: C, for entity: Entity) {
        if let old = valueByEntity[entity] {
            guard old != value else { return }
            entitiesByValue[old]?.removeAll { $0 == entity }
            if entitiesByValue[old]?.isEmpty == true { entitiesByValue[old] = nil }
        }
        valueByEntity[entity] = value
        entitiesByValue[value, default: []].append(entity)
    }

    @inlinable
    mutating func remove(_ entity: Entity) {
        guard let old = valueByEntity.removeValue(forKey: entity) else { return }
        entitiesByValue[old]?.removeAll { $0 == entity }
        if entitiesByValue[old]?.isEmpty == true { entitiesByValue[old] = nil }
    }
}

/// A ``ValueIndex`` of any component type, for code that does not know the type.
@usableFromInline
protocol AnyValueIndex: Sendable {
    var version: UInt64 { get set }
    /// Records `entity`'s component, of the index's type.
    mutating func set(_ component: any Component, for entity: Entity)
    mutating func remove(_ entity: Entity)
    /// Refills the index from `world`'s column of its type.
    mutating func rebuild(from world: World)
}

extension ValueIndex: AnyValueIndex {
    @usableFromInline
    mutating func set(_ component: any Component, for entity: Entity) {
        set(component as! C, for: entity)
    }

    @usableFromInline
    mutating func rebuild(from world: World) {
        entitiesByValue = [:]
        valueByEntity = [:]
        guard let column = world.column(of: C.self) else {
            version = 0
            return
        }
        for (entity, value) in zip(column.index.dense, column.values) {
            set(value, for: entity)
        }
        version = column.writeVersion
    }
}

extension World {
    // MARK: Indexes by value

    /// Keeps a map from each value of `C` to the entities holding it, so ``lookup(_:)`` finds
    /// them without walking the type's storage.
    ///
    /// ```swift
    /// world.index(Name.self)
    /// world.lookup(Name("bob"))  // the entities named bob
    /// ```
    ///
    /// Spawning, inserting, removing and despawning keep the index current. A change made in
    /// place (the subscript, ``update(_:reading:where:body:)``, a span) leaves it out of date
    /// until ``advanceChangeTick()``, which a schedule calls before each system, rebuilds it;
    /// until then ``lookup(_:)`` walks the storage, so its answer is always current. Index a
    /// type whose values change rarely. Indexing a type twice keeps one index. A copy of the
    /// world keeps its indexes; a snapshot does not.
    ///
    /// - Complexity: O(*n*) for *n* entities holding a `C`.
    @inlinable
    public mutating func index<C: Component & Hashable>(_ type: C.Type) {
        let key = ObjectIdentifier(C.self)
        guard valueIndexes[key] == nil else { return }
        let slot = columnSlot(of: C.self)
        columns[slot].isIndexed = true
        var index = ValueIndex<C>()
        index.rebuild(from: self)
        valueIndexes[key] = index
    }

    /// The entities holding a `C` equal to `value`, in no particular order.
    ///
    /// - Complexity: O(*k*) for *k* entities found when `C` is indexed (``index(_:)``) and its
    ///   index is current; otherwise O(*n*) for *n* entities holding a `C`.
    @inlinable
    public func lookup<C: Component & Hashable>(_ value: C) -> [Entity] {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return [] }
        let column = unsafeDowncast(columns[slot], to: Column<C>.self)
        if let index = valueIndexes[ObjectIdentifier(C.self)] as? ValueIndex<C>, index.version == column.writeVersion {
            return index.entitiesByValue[value] ?? []
        }
        var found: [Entity] = []
        for (entity, candidate) in zip(column.index.dense, column.values) where candidate == value {
            found.append(entity)
        }
        return found
    }

    /// Brings the index of `C` up to date with `entity`'s component, just stored (`stored`) or
    /// removed (nil), when no other write left it behind.
    @usableFromInline
    @inline(never)
    mutating func reindexValue<C: Component>(_ type: C.Type, of entity: Entity, stored: C?, slot: Int) {
        let key = ObjectIdentifier(C.self)
        guard var index = valueIndexes[key] else { return }
        let version = columns[slot].writeVersion
        guard index.version == version || index.version == version &- 1 else { return }
        valueIndexes[key] = nil
        if let stored {
            index.set(stored, for: entity)
        } else {
            index.remove(entity)
        }
        index.version = version
        valueIndexes[key] = index
    }

    /// Removes `entity`, which is being despawned, from every index it is current with.
    @usableFromInline
    @inline(never)
    mutating func leaveValueIndexes(_ entity: Entity) {
        for key in Array(valueIndexes.keys) {
            guard let slot = columnPositions.position(of: key), var index = valueIndexes[key],
                  index.version == columns[slot].writeVersion else { continue }
            valueIndexes[key] = nil
            index.remove(entity)
            valueIndexes[key] = index
        }
    }

    /// Rebuilds every index a change in place left out of date.
    @usableFromInline
    @inline(never)
    mutating func refreshValueIndexes() {
        for key in Array(valueIndexes.keys) {
            guard let slot = columnPositions.position(of: key), var index = valueIndexes[key],
                  index.version != columns[slot].writeVersion else { continue }
            valueIndexes[key] = nil
            index.rebuild(from: self)
            valueIndexes[key] = index
        }
    }
}
