import BTrees

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
    // A world reaches the index through `AnyValueIndex`, whose witnesses run unspecialized, so
    // the dictionaries' work goes through closures made where `C` and `Key` are known.
    @usableFromInline let recordComponent: @Sendable (inout Self, C, Entity) -> Void
    @usableFromInline let forgetEntity: @Sendable (inout Self, Entity) -> Void

    @inlinable
    init(key: @escaping @Sendable (C) -> Key) {
        self.key = key
        recordComponent = { index, component, entity in index.record(component, for: entity) }
        forgetEntity = { index, entity in index.forget(entity) }
    }

    @inlinable
    mutating func record(_ component: C, for entity: Entity) {
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
    mutating func forget(_ entity: Entity) {
        guard let old = valueByEntity.removeValue(forKey: entity) else { return }
        entitiesByValue[old]?.removeAll { $0 == entity }
        if entitiesByValue[old]?.isEmpty == true { entitiesByValue[old] = nil }
    }
}

/// An entity of an ordered value index, ordered by its key and then by the entity.
@usableFromInline
struct OrderedIndexEntry<Key: Comparable & Sendable>: Comparable, Sendable {
    @usableFromInline let key: Key
    @usableFromInline let entity: Entity

    @inlinable
    init(key: Key, entity: Entity) {
        self.key = key
        self.entity = entity
    }

    @inlinable
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.key, lhs.entity) < (rhs.key, rhs.entity)
    }
}

/// The entities holding a component type, sorted by a key of the component, as of a version of
/// its column.
@usableFromInline
struct OrderedValueIndex<C: Component, Key: Comparable & Sendable>: Sendable {
    /// The key a component is sorted by.
    @usableFromInline let key: @Sendable (C) -> Key
    @usableFromInline var entries = BTree<OrderedIndexEntry<Key>>()
    @usableFromInline var valueByEntity: [Entity: Key] = [:]
    /// The column's write version the index agrees with.
    @usableFromInline var version: UInt64 = 0
    // A world reaches the index through `AnyValueIndex`, whose witnesses run unspecialized, so
    // the tree's work goes through closures made where `C` and `Key` are known.
    @usableFromInline let recordComponent: @Sendable (inout Self, C, Entity) -> Void
    @usableFromInline let forgetEntity: @Sendable (inout Self, Entity) -> Void

    @inlinable
    init(key: @escaping @Sendable (C) -> Key) {
        self.key = key
        recordComponent = { index, component, entity in index.record(component, for: entity) }
        forgetEntity = { index, entity in index.forget(entity) }
    }

    @inlinable
    mutating func record(_ component: C, for entity: Entity) {
        let value = key(component)
        precondition(value == value, "An ordered index's key must equal itself; \(value) doesn't")
        if let old = valueByEntity[entity] {
            guard old != value else { return }
            entries.remove(OrderedIndexEntry(key: old, entity: entity))
        }
        valueByEntity[entity] = value
        entries.insert(OrderedIndexEntry(key: value, entity: entity))
    }

    @inlinable
    mutating func forget(_ entity: Entity) {
        guard let old = valueByEntity.removeValue(forKey: entity) else { return }
        entries.remove(OrderedIndexEntry(key: old, entity: entity))
    }

    /// The positions in `entries` of the entities whose key falls in `range`, or nil for a kind
    /// of range whose bounds aren't known.
    @inlinable
    func positions(in range: some RangeExpression<Key>) -> Range<Int>? {
        let first = Entity(index: 0, generation: 0)
        let last = Entity(index: .max, generation: .max)
        switch range {
        case let range as Range<Key>:
            return entries.lowerBound(OrderedIndexEntry(key: range.lowerBound, entity: first))
                ..< entries.lowerBound(OrderedIndexEntry(key: range.upperBound, entity: first))
        case let range as ClosedRange<Key>:
            return entries.lowerBound(OrderedIndexEntry(key: range.lowerBound, entity: first))
                ..< entries.upperBound(OrderedIndexEntry(key: range.upperBound, entity: last))
        case let range as PartialRangeFrom<Key>:
            return entries.lowerBound(OrderedIndexEntry(key: range.lowerBound, entity: first)) ..< entries.count
        case let range as PartialRangeThrough<Key>:
            return 0 ..< entries.upperBound(OrderedIndexEntry(key: range.upperBound, entity: last))
        case let range as PartialRangeUpTo<Key>:
            return 0 ..< entries.lowerBound(OrderedIndexEntry(key: range.upperBound, entity: first))
        default:
            return nil
        }
    }
}

extension OrderedValueIndex: AnyValueIndex {
    @usableFromInline
    mutating func set(_ component: any Component, for entity: Entity) {
        let record = recordComponent
        record(&self, component as! C, entity)
    }

    @usableFromInline
    mutating func remove(_ entity: Entity) {
        let forget = forgetEntity
        forget(&self, entity)
    }

    @usableFromInline
    mutating func rebuild(from world: World) {
        entries = BTree()
        valueByEntity = [:]
        guard let column = world.column(of: C.self) else {
            version = 0
            return
        }
        let record = recordComponent
        for (entity, value) in zip(column.index.dense, column.values) {
            record(&self, value, entity)
        }
        version = column.writeVersion
    }
}

/// What a value index is kept for: a component type, the key path of the property it is keyed
/// by, or `nil` when it is keyed by the whole component, and whether it is sorted by that key.
@usableFromInline
struct ValueIndexKey: Hashable, @unchecked Sendable {
    // Key paths are immutable, so sharing one across threads is safe.
    @usableFromInline let type: ObjectIdentifier
    @usableFromInline let path: AnyKeyPath?
    @usableFromInline let isOrdered: Bool

    @inlinable
    init(type: ObjectIdentifier, path: AnyKeyPath?, isOrdered: Bool = false) {
        self.type = type
        self.path = path
        self.isOrdered = isOrdered
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
        let record = recordComponent
        record(&self, component as! C, entity)
    }

    @usableFromInline
    mutating func remove(_ entity: Entity) {
        let forget = forgetEntity
        forget(&self, entity)
    }

    @usableFromInline
    mutating func rebuild(from world: World) {
        entitiesByValue = [:]
        valueByEntity = [:]
        guard let column = world.column(of: C.self) else {
            version = 0
            return
        }
        let record = recordComponent
        for (entity, value) in zip(column.index.dense, column.values) {
            record(&self, value, entity)
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

    /// Keeps the entities holding a component type sorted by a property of the component, so
    /// that ``lookup(_:in:)`` finds the entities whose property falls in a range, and
    /// ``entities(sortedBy:)`` lists them in order, without walking and sorting the type's
    /// storage.
    ///
    /// Use an ordered index when you often ask for the entities whose property lies between two
    /// values, such as the ones whose health runs low, or visit entities in the order of a
    /// property, such as drawing them back to front:
    ///
    /// ```swift
    /// var world = World()
    /// let weak = world.spawn(Health(current: 2))
    /// let weaker = world.spawn(Health(current: 1))
    /// world.spawn(Health(current: 9))
    /// world.index(ordered: \Health.current)
    ///
    /// print(world.lookup(\Health.current, in: ...3) == [weaker, weak])
    /// // Prints "true"
    /// ```
    ///
    /// An ordered index is kept current the same way as an index by value (``index(_:)-u1gw``):
    /// spawning, inserting, removing and despawning update it; a change in place leaves it out of
    /// date until the next ``advanceChangeTick()``, and until then ``lookup(_:in:)`` and
    /// ``entities(sortedBy:)`` walk and sort the storage, so their answers are always current.
    /// Keeping it costs O(log *n*) for each insert, removal and despawn of an entity holding a
    /// `C`, where an index by value costs O(1), so index a key path ordered only when you look it
    /// up by range or order. Indexing the same key path ordered twice keeps one index; a key path
    /// can have an ordered index and an index by value at once.
    ///
    /// - Parameter key: The key path of the property to sort the component type's entities by.
    /// - Precondition: Every key equals itself; a floating-point key isn't NaN.
    /// - Complexity: O(*n* log *n*) for *n* entities holding a `C`.
    @inlinable
    public mutating func index<C: Component, Key: Comparable & Sendable>(ordered key: KeyPath<C, Key> & Sendable) {
        let indexKey = ValueIndexKey(type: ObjectIdentifier(C.self), path: key, isOrdered: true)
        guard valueIndexes[indexKey] == nil else { return }
        let slot = columnSlot(of: C.self)
        columns[slot].isIndexed = true
        var index = OrderedValueIndex<C, Key>(key: { $0[keyPath: key] })
        index.rebuild(from: self)
        valueIndexes[indexKey] = index
    }

    /// Returns the entities holding a component whose property at a key path falls in a range,
    /// in the order of that property.
    ///
    /// The method answers from the key path's ordered index when you've made one with
    /// ``index(ordered:)`` and the index is current, and walks and sorts the type's storage
    /// otherwise. Either way, the answer reflects every change made so far. Any range works,
    /// closed, half-open or partial:
    ///
    /// ```swift
    /// var world = World()
    /// let healthy = world.spawn(Health(current: 8))
    /// world.spawn(Health(current: 3))
    /// let healthiest = world.spawn(Health(current: 10))
    ///
    /// print(world.lookup(\Health.current, in: 5...) == [healthy, healthiest])
    /// // Prints "true"
    /// ```
    ///
    /// - Parameters:
    ///   - key: The key path of the property to compare.
    ///   - range: The range the property must fall in.
    /// - Returns: The entities holding a component whose property at `key` falls in `range`, in
    ///   ascending order of that property, and of entity where the property is equal.
    /// - Precondition: Every key equals itself; a floating-point key isn't NaN.
    /// - Complexity: O(*k* log *n*) for *k* entities found when `key` has a current ordered
    ///   index, of *n* entries; otherwise O(*n* log *n*) for *n* entities holding a `C`.
    @inlinable
    public func lookup<C: Component, Key: Comparable & Sendable>(_ key: KeyPath<C, Key> & Sendable, in range: some RangeExpression<Key>) -> [Entity] {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return [] }
        let column = unsafeDowncast(columns[slot], to: Column<C>.self)
        if let index = valueIndexes[ValueIndexKey(type: ObjectIdentifier(C.self), path: key, isOrdered: true)] as? OrderedValueIndex<C, Key>,
           index.version == column.writeVersion {
            if let positions = index.positions(in: range) {
                return index.entries[positions].map(\.entity)
            }
            return index.entries.filter { range.contains($0.key) }.map(\.entity)
        }
        var found: [OrderedIndexEntry<Key>] = []
        for (entity, candidate) in zip(column.index.dense, column.values) {
            let value = candidate[keyPath: key]
            precondition(value == value, "An ordered lookup's key must equal itself; \(value) doesn't")
            if range.contains(value) { found.append(OrderedIndexEntry(key: value, entity: entity)) }
        }
        return found.sorted().map(\.entity)
    }

    /// Returns the entities holding a component type, in the order of a property of the
    /// component.
    ///
    /// The method answers from the key path's ordered index when you've made one with
    /// ``index(ordered:)`` and the index is current, and sorts the type's storage otherwise.
    /// Either way, the answer reflects every change made so far:
    ///
    /// ```swift
    /// var world = World()
    /// let middle = world.spawn(Health(current: 5))
    /// let low = world.spawn(Health(current: 1))
    /// let high = world.spawn(Health(current: 7))
    /// world.index(ordered: \Health.current)
    ///
    /// print(world.entities(sortedBy: \Health.current) == [low, middle, high])
    /// // Prints "true"
    /// ```
    ///
    /// - Parameter key: The key path of the property to sort by.
    /// - Returns: The entities holding a `C`, in ascending order of the property at `key`, and of
    ///   entity where the property is equal.
    /// - Precondition: Every key equals itself; a floating-point key isn't NaN.
    /// - Complexity: O(*n*) for *n* entities holding a `C` when `key` has a current ordered
    ///   index; otherwise O(*n* log *n*).
    @inlinable
    public func entities<C: Component, Key: Comparable & Sendable>(sortedBy key: KeyPath<C, Key> & Sendable) -> [Entity] {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return [] }
        let column = unsafeDowncast(columns[slot], to: Column<C>.self)
        if let index = valueIndexes[ValueIndexKey(type: ObjectIdentifier(C.self), path: key, isOrdered: true)] as? OrderedValueIndex<C, Key>,
           index.version == column.writeVersion {
            // The tree's own iterator walks it in O(n); `map` would look up each position.
            var sorted: [Entity] = []
            sorted.reserveCapacity(index.entries.count)
            for entry in index.entries { sorted.append(entry.entity) }
            return sorted
        }
        var found: [OrderedIndexEntry<Key>] = []
        found.reserveCapacity(column.values.count)
        for (entity, candidate) in zip(column.index.dense, column.values) {
            let value = candidate[keyPath: key]
            precondition(value == value, "An ordered lookup's key must equal itself; \(value) doesn't")
            found.append(OrderedIndexEntry(key: value, entity: entity))
        }
        return found.sorted().map(\.entity)
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
