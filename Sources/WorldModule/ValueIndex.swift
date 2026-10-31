/// The entities holding each key of a component type, where a component's key is the component
/// itself or a property of it, as of a version of its column.
@usableFromInline
struct ValueIndex<C: Component, Key: Hashable & Sendable>: Sendable {
    /// The key a component is found by.
    @usableFromInline let key: @Sendable (C) -> Key
    @usableFromInline var entitiesByValue: [Key: [Entity]] = [:]
    @usableFromInline var valueByEntity: [Entity: Key] = [:]
    /// The column's write version the index agrees with.
    @usableFromInline var version: UInt64 = 0

    @inlinable
    init(key: @escaping @Sendable (C) -> Key) {
        self.key = key
    }

    @inlinable
    mutating func set(_ component: C, for entity: Entity) {
        let value = key(component)
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

/// What a value index is kept for: a component type, and the key path of the property it is
/// keyed by, or `nil` when it is keyed by the whole component.
@usableFromInline
struct ValueIndexKey: Hashable, @unchecked Sendable {
    // Key paths are immutable, so sharing one across threads is safe.
    @usableFromInline let type: ObjectIdentifier
    @usableFromInline let path: AnyKeyPath?

    @inlinable
    init(type: ObjectIdentifier, path: AnyKeyPath?) {
        self.type = type
        self.path = path
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

    /// Keeps a map from each value of a component type to the entities holding it, so that
    /// ``lookup(_:)`` finds them without walking the type's storage.
    ///
    /// Use an index when you often look entities up by a component's value, such as finding an
    /// entity by its name:
    ///
    /// ```swift
    /// var world = World()
    /// let bob = world.spawn(Name(value: "bob"), Health(current: 3))
    /// world.spawn(Name(value: "ada"), Health(current: 4))
    /// world.index(Name.self)
    ///
    /// print(world.lookup(Name(value: "bob")) == [bob])
    /// // Prints "true"
    /// ```
    ///
    /// Spawning, inserting, removing and despawning keep the index current. A change made in place,
    /// through the world's subscript, an update or a mutable span, leaves the index out of date
    /// until the next ``advanceChangeTick()``, which a schedule calls before each system, rebuilds
    /// it. Until then, ``lookup(_:)`` walks the storage, so its answer is always current. Index a
    /// type whose values change rarely. Indexing a type twice keeps one index. A copy of the world
    /// keeps its indexes; a snapshot doesn't.
    ///
    /// - Parameter type: The component type to index.
    /// - Complexity: O(*n*) for *n* entities holding a `C`.
    @inlinable
    public mutating func index<C: Component & Hashable>(_ type: C.Type) {
        let key = ValueIndexKey(type: ObjectIdentifier(C.self), path: nil)
        guard valueIndexes[key] == nil else { return }
        let slot = columnSlot(of: C.self)
        columns[slot].isIndexed = true
        var index = ValueIndex<C, C>(key: { $0 })
        index.rebuild(from: self)
        valueIndexes[key] = index
    }

    /// Returns the entities holding a component equal to the given value.
    ///
    /// The method answers from the type's index when you've indexed it with ``index(_:)-u1gw``
    /// and the index is current, and walks the type's storage otherwise. Either way, the answer
    /// reflects every change made so far.
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Name(value: "guard"))
    /// world.spawn(Name(value: "guard"))
    /// world.spawn(Name(value: "king"))
    ///
    /// print(world.lookup(Name(value: "guard")).count)
    /// // Prints "2"
    /// ```
    ///
    /// - Parameter value: The value to look for.
    /// - Returns: The entities holding a component equal to `value`, in no particular order.
    /// - Complexity: O(*k*) for *k* entities found when `C` is indexed (``index(_:)-u1gw``) and its
    ///   index is current; otherwise O(*n*) for *n* entities holding a `C`.
    @inlinable
    public func lookup<C: Component & Hashable>(_ value: C) -> [Entity] {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return [] }
        let column = unsafeDowncast(columns[slot], to: Column<C>.self)
        if let index = valueIndexes[ValueIndexKey(type: ObjectIdentifier(C.self), path: nil)] as? ValueIndex<C, C>, index.version == column.writeVersion {
            return index.entitiesByValue[value] ?? []
        }
        var found: [Entity] = []
        for (entity, candidate) in zip(column.index.dense, column.values) where candidate == value {
            found.append(entity)
        }
        return found
    }

    /// Keeps a map from each value of a component's property to the entities holding it, so that
    /// ``lookup(_:equals:)`` finds them without walking the type's storage.
    ///
    /// Use a keyed index when you look entities up by one property of a component rather than
    /// by the whole value, such as finding a seat by its number without knowing who sits in it:
    ///
    /// ```swift
    /// struct Seat: Component { var row: Int, number: Int }
    ///
    /// var world = World()
    /// let front = world.spawn(Seat(row: 1, number: 7))
    /// world.spawn(Seat(row: 2, number: 3))
    /// world.index(\Seat.number)
    ///
    /// print(world.lookup(\Seat.number, equals: 7) == [front])
    /// // Prints "true"
    /// ```
    ///
    /// A keyed index is kept current the same way as an index by value (``index(_:)-u1gw``):
    /// spawning, inserting, removing and despawning update it; a change in place leaves it out of
    /// date until the next ``advanceChangeTick()``, and until then ``lookup(_:equals:)`` walks the
    /// storage, so its answer is always current. Indexing the same key path twice keeps one
    /// index; a type can have indexes on several key paths.
    ///
    /// - Parameter key: The key path of the property to index the component type by.
    /// - Complexity: O(*n*) for *n* entities holding a `C`.
    @inlinable
    public mutating func index<C: Component, Key: Hashable & Sendable>(_ key: KeyPath<C, Key> & Sendable) {
        let indexKey = ValueIndexKey(type: ObjectIdentifier(C.self), path: key)
        guard valueIndexes[indexKey] == nil else { return }
        let slot = columnSlot(of: C.self)
        columns[slot].isIndexed = true
        var index = ValueIndex<C, Key>(key: { $0[keyPath: key] })
        index.rebuild(from: self)
        valueIndexes[indexKey] = index
    }

    /// Returns the entities holding a component whose property at a key path equals the given
    /// value.
    ///
    /// The method answers from the key path's index when you've made one with ``index(_:)-2gtfg``
    /// and the index is current, and walks the type's storage otherwise. Either way, the answer
    /// reflects every change made so far:
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Seat(row: 1, number: 7))
    /// world.spawn(Seat(row: 2, number: 7))
    ///
    /// print(world.lookup(\Seat.number, equals: 7).count)
    /// // Prints "2"
    /// ```
    ///
    /// - Parameters:
    ///   - key: The key path of the property to compare.
    ///   - value: The value to look for.
    /// - Returns: The entities holding a component whose property at `key` equals `value`, in no
    ///   particular order.
    /// - Complexity: O(*k*) for *k* entities found when `key` is indexed and its index is
    ///   current; otherwise O(*n*) for *n* entities holding a `C`.
    @inlinable
    public func lookup<C: Component, Key: Hashable & Sendable>(_ key: KeyPath<C, Key> & Sendable, equals value: Key) -> [Entity] {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return [] }
        let column = unsafeDowncast(columns[slot], to: Column<C>.self)
        if let index = valueIndexes[ValueIndexKey(type: ObjectIdentifier(C.self), path: key)] as? ValueIndex<C, Key>, index.version == column.writeVersion {
            return index.entitiesByValue[value] ?? []
        }
        var found: [Entity] = []
        for (entity, candidate) in zip(column.index.dense, column.values) where candidate[keyPath: key] == value {
            found.append(entity)
        }
        return found
    }

    /// Brings the indexes of `C` up to date with `entity`'s component, just stored (`stored`) or
    /// removed (nil), when no other write left them behind.
    @usableFromInline
    @inline(never)
    mutating func reindexValue<C: Component>(_ type: C.Type, of entity: Entity, stored: C?, slot: Int) {
        let type = ObjectIdentifier(C.self)
        let version = columns[slot].writeVersion
        // Each index is changed in place through the values, which allocates nothing.
        var position = valueIndexes.startIndex
        while position != valueIndexes.endIndex {
            defer { position = valueIndexes.index(after: position) }
            guard valueIndexes.keys[position].type == type else { continue }
            let indexVersion = valueIndexes.values[position].version
            guard indexVersion == version || indexVersion == version &- 1 else { continue }
            if let stored {
                valueIndexes.values[position].set(stored, for: entity)
            } else {
                valueIndexes.values[position].remove(entity)
            }
            valueIndexes.values[position].version = version
        }
    }

    /// Removes `entity`, which is being despawned, from every index it is current with.
    @usableFromInline
    @inline(never)
    mutating func leaveValueIndexes(_ entity: Entity) {
        for key in Array(valueIndexes.keys) {
            guard let slot = columnPositions.position(of: key.type), var index = valueIndexes[key],
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
            guard let slot = columnPositions.position(of: key.type), var index = valueIndexes[key],
                  index.version != columns[slot].writeVersion else { continue }
            valueIndexes[key] = nil
            index.rebuild(from: self)
            valueIndexes[key] = index
        }
    }
}
