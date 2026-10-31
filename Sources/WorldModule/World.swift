/// Entities, the components they hold, and the world's resources.
///
/// A world is a value: a copy is independent of the original, and copying is cheap because each
/// component type's storage is shared between copies until one of them writes to it, and then
/// only that type's storage is copied.
///
/// Components of one type are stored in a sparse set: a dense array of components with a sparse
/// array from entity slot to position. Reading, adding, replacing and removing one component are
/// O(1), and iterating a type is a walk over contiguous memory.
///
/// Operations that take an ``Entity`` trap when it is stale, like an array subscript out of
/// range. Each has a `checked` spelling that throws instead.
///
/// ```swift
/// var world = World()
/// let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
/// world.update(Position.self, reading: Velocity.self) { position, row in
///     position.x += row.components.dx
///     position.y += row.components.dy
/// }
/// world[Position.self, of: ball]  // Position(x: 1, y: 2)
/// ```
@frozen
public struct World: Sendable {
    /// The generation of each slot's current or next entity.
    @usableFromInline var generations: [UInt32] = []
    /// Whether each slot holds a live entity.
    @usableFromInline var isLive: [Bool] = []
    /// Vacated slots, the most recently vacated last.
    @usableFromInline var vacant: [UInt32] = []
    /// One column per component type ever stored, in the order the types were first stored.
    @usableFromInline var columns: ContiguousArray<AnyColumn> = []
    @usableFromInline var columnPositions = ColumnTable()
    /// The parent and children of every entity.
    @usableFromInline var hierarchy = Hierarchy()
    /// The component hooks and the hook calls waiting to run.
    @usableFromInline var hooks = Hooks()
    /// The owning groups, each column knowing its group by position here.
    @usableFromInline var groups: [OwningGroup] = []
    /// Counts changes to which entities are live and to the hierarchy.
    @usableFromInline var structureVersion: UInt64 = 0
    /// Command buffers queued with ``queue(_:)``, in the order they were queued.
    @usableFromInline var queuedCommands: [Commands] = []

    /// The world's resources: values it holds once, outside any entity.
    public var resources = Resources()

    /// The tick the world stamps on every component it adds or changes.
    ///
    /// It starts at 1 and moves only through ``advanceChangeTick()``, which a schedule calls
    /// before each system it runs.
    public var changeTick: ChangeTick { storedChangeTick }
    @usableFromInline var storedChangeTick = ChangeTick(1)

    /// The change tick at which the running system last ran, or ``ChangeTick/zero`` if it has not
    /// run before or no schedule is running.
    ///
    /// Filters such as ``QueryFilter/changed(_:since:)`` compare against it when given no tick, so
    /// a system sees what changed since its previous run. A ``Schedule`` sets it around each
    /// system; set it directly only when running systems without one.
    public var lastRun = ChangeTick.zero

    /// Starts a new change tick: components added or changed from now on are newer than every
    /// earlier tick.
    ///
    /// ```swift
    /// let checkpoint = world.changeTick
    /// world.advanceChangeTick()
    /// world[Health.self, of: hero].current -= 1
    /// world.query(Health.self).changed(Health.self, since: checkpoint)  // hero
    /// ```
    ///
    /// - Returns: The new tick.
    @inlinable
    @discardableResult
    public mutating func advanceChangeTick() -> ChangeTick {
        storedChangeTick = ChangeTick(storedChangeTick.value + 1)
        return storedChangeTick
    }

    /// A world without entities or resources.
    @inlinable
    public init() {}

    // MARK: Entities

    /// The number of live entities.
    @inlinable
    public var count: Int { generations.count - vacant.count }

    /// Whether the world has no live entities.
    @inlinable
    public var isEmpty: Bool { count == 0 }

    /// The live entities, lazily, in slot order.
    @inlinable
    public var entities: EntitiesView { EntitiesView(generations: generations, isLive: isLive) }

    /// Whether `entity` is live in this world.
    ///
    /// - Complexity: O(1).
    @inlinable
    public func contains(_ entity: Entity) -> Bool {
        let slot = Int(entity.index)
        return slot < generations.count && isLive[slot] && generations[slot] == entity.generation
    }

    /// Spawns an entity holding the components of `bundles` and returns its handle.
    ///
    /// Each component is a bundle of itself, so `spawn(Position(x: 0, y: 0), Velocity(dx: 1,
    /// dy: 0))` spawns an entity holding both. Spawning one, two or three components has
    /// overloads specialized for speed.
    ///
    /// A vacated slot is reused, the most recently vacated first, with a generation one higher
    /// than its last entity's. When the bundles hold two components of one type, the later one
    /// is kept.
    ///
    /// - Complexity: O(*k*) amortized for *k* components.
    /// - Precondition: Fewer than `UInt32.max` slots are in use.
    @inlinable
    @discardableResult
    public mutating func spawn<each B: Bundle>(_ bundles: repeat each B) -> Entity {
        let entity = makeEntity()
        for bundle in repeat each bundles {
            bundle.insert(into: entity, in: &self)
        }
        for bundle in repeat each bundles {
            bundle._insertRequired(into: entity, in: &self)
        }
        endOperation()
        return entity
    }

    /// Spawns an entity holding the components of `bundle` and returns its handle, as the
    /// variadic `spawn` does.
    @inlinable
    @discardableResult
    public mutating func spawn<B: Bundle>(_ bundle: B) -> Entity {
        let entity = makeEntity()
        bundle.insert(into: entity, in: &self)
        bundle._insertRequired(into: entity, in: &self)
        endOperation()
        return entity
    }

    /// Spawns an entity holding `a` and returns its handle, as the variadic `spawn` does.
    @inlinable
    @discardableResult
    public mutating func spawn<A: Component>(_ a: A) -> Entity {
        let entity = makeEntity()
        store(a, for: entity)
        a._insertRequired(into: entity, in: &self)
        endOperation()
        return entity
    }

    /// Spawns an entity holding `a` and `b` and returns its handle, as the variadic `spawn` does.
    @inlinable
    @discardableResult
    public mutating func spawn<A: Component, B: Component>(_ a: A, _ b: B) -> Entity {
        let entity = makeEntity()
        store(a, for: entity)
        store(b, for: entity)
        a._insertRequired(into: entity, in: &self)
        b._insertRequired(into: entity, in: &self)
        endOperation()
        return entity
    }

    /// Spawns an entity holding `a`, `b` and `c` and returns its handle, as the variadic `spawn`
    /// does.
    @inlinable
    @discardableResult
    public mutating func spawn<A: Component, B: Component, C: Component>(_ a: A, _ b: B, _ c: C) -> Entity {
        let entity = makeEntity()
        store(a, for: entity)
        store(b, for: entity)
        store(c, for: entity)
        a._insertRequired(into: entity, in: &self)
        b._insertRequired(into: entity, in: &self)
        c._insertRequired(into: entity, in: &self)
        endOperation()
        return entity
    }

    /// Despawns `entity`, its descendants and every component they hold, and detaches it from
    /// its parent. Every copy of their handles is stale from now on.
    ///
    /// - Complexity: O(*n*·*t*) for *n* entities despawned and *t* component types the world has
    ///   stored.
    /// - Precondition: `entity` is live. Use ``despawn(checked:)`` to throw instead.
    @inlinable
    public mutating func despawn(_ entity: Entity) {
        precondition(contains(entity), "Despawning stale entity \(entity)")
        if hierarchy.links == 0 {
            destroy(entity)
        } else {
            destroySubtree(entity)
        }
        endOperation()
    }

    /// Despawns `entity`, its descendants and every component they hold, and detaches it from
    /// its parent.
    ///
    /// - Complexity: O(*n*·*t*) for *n* entities despawned and *t* component types the world has
    ///   stored.
    /// - Throws: ``StaleEntity`` when `entity` is not live; the world is unchanged.
    @inlinable
    public mutating func despawn(checked entity: Entity) throws(StaleEntity) {
        guard contains(entity) else { throw StaleEntity() }
        if hierarchy.links == 0 {
            destroy(entity)
        } else {
            destroySubtree(entity)
        }
        endOperation()
    }

    // MARK: Components

    /// Whether `entity` is live and holds a `C`.
    ///
    /// - Complexity: O(1).
    @inlinable
    public func contains<C: Component>(_ type: C.Type, in entity: Entity) -> Bool {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return false }
        return unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { $0.index.position(of: entity) != nil }
    }

    /// The `C` that `entity` holds.
    ///
    /// Writing through the subscript changes the component in place, and marks it changed at the
    /// current ``changeTick``: `world[Health.self, of: hero].current -= 10`.
    ///
    /// - Complexity: O(1), plus a copy of the `C` storage on the first write after the world was
    ///   copied.
    /// - Precondition: `entity` is live and holds a `C`. Use ``subscript(checked:of:)`` to throw
    ///   instead.
    @inlinable
    public subscript<C: Component>(_ type: C.Type, of entity: Entity) -> C {
        get {
            precondition(contains(entity), "Reading a \(C.self) of stale entity \(entity)")
            guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else {
                preconditionFailure("Entity \(entity) holds no \(C.self)")
            }
            return unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { column in
                guard let position = column.index.position(of: entity) else {
                    preconditionFailure("Entity \(entity) holds no \(C.self)")
                }
                return column.values[position]
            }
        }
        _modify {
            precondition(contains(entity), "Writing a \(C.self) of stale entity \(entity)")
            guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)),
                  let position = columns[slot].index.position(of: entity) else {
                preconditionFailure("Entity \(entity) holds no \(C.self)")
            }
            // Moved out while it is written: yielding storage inside the column would retain the
            // column for the duration.
            let column = uniqueUnretainedColumn(at: slot, of: C.self)
            let tick = changeTick
            column._withUnsafeGuaranteedRef { $0.index.ticks[position].changed = tick }
            var values: [C] = []
            column._withUnsafeGuaranteedRef { swap(&values, &$0.values) }
            defer { column._withUnsafeGuaranteedRef { swap(&values, &$0.values) } }
            yield &values[position]
        }
    }

    /// The `C` that `entity` holds.
    ///
    /// `try?` gives `nil` when there is none.
    ///
    /// - Complexity: O(1).
    /// - Throws: ``MissingComponent`` when `entity` is stale or holds no `C`.
    @inlinable
    public subscript<C: Component>(checked type: C.Type, of entity: Entity) -> C {
        get throws(MissingComponent) {
            guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { throw MissingComponent() }
            let component: C? = unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { column in
                column.index.position(of: entity).map { column.values[$0] }
            }
            guard let component else { throw MissingComponent() }
            return component
        }
    }

    /// Gives `entity` the components of `bundles`, replacing any it holds of the same types.
    ///
    /// Each component is a bundle of itself. A new component is marked added and changed at the
    /// current ``changeTick``; a replaced one, changed.
    ///
    /// - Complexity: O(*k*) amortized for *k* components.
    /// - Precondition: `entity` is live. Use ``insert(_:checkedInto:)`` to throw instead.
    @inlinable
    public mutating func insert<each B: Bundle>(_ bundles: repeat each B, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        for bundle in repeat each bundles {
            bundle.insert(into: entity, in: &self)
        }
        for bundle in repeat each bundles {
            bundle._insertRequired(into: entity, in: &self)
        }
        endOperation()
    }

    /// Gives `entity` the components of `bundle`, replacing any it holds of the same types, as
    /// the variadic `insert` does.
    ///
    /// - Complexity: O(*k*) amortized for *k* components.
    /// - Precondition: `entity` is live. Use ``insert(_:checkedInto:)`` to throw instead.
    @inlinable
    public mutating func insert<B: Bundle>(_ bundle: B, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        bundle.insert(into: entity, in: &self)
        bundle._insertRequired(into: entity, in: &self)
        endOperation()
    }

    /// Gives `entity` the component `a`, replacing any it holds of its type.
    ///
    /// - Complexity: O(1) amortized.
    /// - Precondition: `entity` is live. Use ``insert(_:checkedInto:)`` to throw instead.
    @inlinable
    public mutating func insert<A: Component>(_ a: A, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        store(a, for: entity)
        a._insertRequired(into: entity, in: &self)
        endOperation()
    }

    /// Gives `entity` the components `a` and `b`, replacing any it holds of their types.
    ///
    /// - Complexity: O(1) amortized.
    /// - Precondition: `entity` is live. Use ``insert(_:checkedInto:)`` to throw instead.
    @inlinable
    public mutating func insert<A: Component, B: Component>(_ a: A, _ b: B, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        store(a, for: entity)
        store(b, for: entity)
        a._insertRequired(into: entity, in: &self)
        b._insertRequired(into: entity, in: &self)
        endOperation()
    }

    /// Gives `entity` the components `a`, `b` and `c`, replacing any it holds of their types.
    ///
    /// - Complexity: O(1) amortized.
    /// - Precondition: `entity` is live. Use ``insert(_:checkedInto:)`` to throw instead.
    @inlinable
    public mutating func insert<A: Component, B: Component, C: Component>(_ a: A, _ b: B, _ c: C, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        store(a, for: entity)
        store(b, for: entity)
        store(c, for: entity)
        a._insertRequired(into: entity, in: &self)
        b._insertRequired(into: entity, in: &self)
        c._insertRequired(into: entity, in: &self)
        endOperation()
    }

    /// Gives `entity` the components of `bundles`, replacing any it holds of the same types.
    ///
    /// - Complexity: O(*k*) amortized for *k* components.
    /// - Throws: ``StaleEntity`` when `entity` is not live; the world is unchanged.
    @inlinable
    public mutating func insert<each B: Bundle>(_ bundles: repeat each B, checkedInto entity: Entity) throws(StaleEntity) {
        guard contains(entity) else { throw StaleEntity() }
        for bundle in repeat each bundles {
            bundle.insert(into: entity, in: &self)
        }
        for bundle in repeat each bundles {
            bundle._insertRequired(into: entity, in: &self)
        }
        endOperation()
    }

    /// Takes the `C` away from `entity`.
    ///
    /// - Returns: The `C` it held, or `nil` if it held none.
    /// - Complexity: O(1). Removal moves the last `C` into the vacated position.
    /// - Precondition: `entity` is live. Use ``remove(_:checkedFrom:)`` to throw instead.
    @inlinable
    @discardableResult
    public mutating func remove<C: Component>(_ type: C.Type, from entity: Entity) -> C? {
        precondition(contains(entity), "Removing a \(C.self) from stale entity \(entity)")
        defer { endOperation() }
        return discard(C.self, from: entity)
    }

    /// Takes the `C` away from `entity`.
    ///
    /// - Returns: The `C` it held, or `nil` if it held none.
    /// - Complexity: O(1).
    /// - Throws: ``StaleEntity`` when `entity` is not live; the world is unchanged.
    @inlinable
    @discardableResult
    public mutating func remove<C: Component>(_ type: C.Type, checkedFrom entity: Entity) throws(StaleEntity) -> C? {
        guard contains(entity) else { throw StaleEntity() }
        defer { endOperation() }
        return discard(C.self, from: entity)
    }

    /// The number of entities that hold a `C`.
    ///
    /// - Complexity: O(1).
    @inlinable
    public func count<C: Component>(of type: C.Type) -> Int {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return 0 }
        return unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { $0.index.dense.count }
    }

    // MARK: Storage

    /// The column at `slot`, without retaining it; valid while this world is not changed.
    @inlinable
    @inline(__always)
    func unretainedColumn<C: Component>(at slot: Int, of type: C.Type) -> Unmanaged<Column<C>> {
        columns.withUnsafeBufferPointer { columns in
            Unmanaged.passUnretained(unsafeDowncast(columns[slot], to: Column<C>.self))
        }
    }

    @inlinable
    func column<C: Component>(of type: C.Type) -> Column<C>? {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return nil }
        return unsafeDowncast(columns[slot], to: Column<C>.self)
    }

    /// The `C` column's contents, empty if the world never stored a `C`.
    @inlinable
    func snapshot<C: Component>(of type: C.Type) -> ColumnSnapshot<C> {
        column(of: C.self)?.snapshot ?? ColumnSnapshot()
    }

    /// The column at `slot`, copied first if another world shares it, without retaining it; valid
    /// while this world is not changed otherwise.
    @inlinable
    @inline(__always)
    mutating func uniqueUnretainedColumn<C: Component>(at slot: Int, of type: C.Type) -> Unmanaged<Column<C>> {
        if !isKnownUniquelyReferenced(&columns[slot]) {
            copyColumn(at: slot)
        }
        return unretainedColumn(at: slot, of: C.self)
    }

    /// The column at `slot`, copied first if another world shares it.
    @inlinable
    mutating func uniqueColumn<C: Component>(at slot: Int, of type: C.Type) -> Column<C> {
        if !isKnownUniquelyReferenced(&columns[slot]) {
            copyColumn(at: slot)
        }
        return unsafeDowncast(columns[slot], to: Column<C>.self)
    }

    @inline(never)
    @usableFromInline
    mutating func copyColumn(at slot: Int) {
        columns[slot] = columns[slot].copy()
    }

    /// The slot of the `C` column, adding an empty column if the world has none.
    @inlinable
    mutating func columnSlot<C: Component>(of type: C.Type) -> Int {
        if let slot = columnPositions.position(of: ObjectIdentifier(C.self)) { return slot }
        columns.append(Column<C>())
        columnPositions.insert(ObjectIdentifier(C.self), at: columns.count - 1)
        return columns.count - 1
    }

    @inlinable
    mutating func store<C: Component>(_ component: C, for entity: Entity) {
        let tick = changeTick
        let group = uniqueUnretainedColumn(at: columnSlot(of: C.self), of: C.self)._withUnsafeGuaranteedRef { column in
            if let position = column.index.position(of: entity) {
                column.values[position] = component
                column.index.ticks[position].changed = tick
                return -2
            } else {
                _ = column.index.append(entity, at: tick)
                column.values.append(component)
                return column.group
            }
        }
        let added = group != -2
        if group >= 0 {
            joinGroup(group, entity)
        }
        if !hooks.isEmpty {
            fireInsertHooks(C.self, for: entity, added: added)
        }
    }

    /// Runs the hook calls the operation that is ending fired.
    @inlinable
    mutating func endOperation() {
        if !hooks.pending.isEmpty {
            runPendingHooks()
        }
    }

    @inlinable
    mutating func discard<C: Component>(_ type: C.Type, from entity: Entity) -> C? {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return nil }
        let group = unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { $0.group }
        if group >= 0 {
            leaveGroup(group, entity)
        }
        guard let position = unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef({ $0.index.position(of: entity) }) else {
            return nil
        }
        let component = uniqueUnretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { column in
            let component = column.values[position]
            column.swapRemove(at: position)
            return component
        }
        if !hooks.isEmpty {
            fireRemoveHooks(component, of: entity)
        }
        return component
    }

    @inlinable
    mutating func makeEntity() -> Entity {
        structureVersion &+= 1
        if let slot = vacant.popLast() {
            isLive[Int(slot)] = true
            return Entity(index: slot, generation: generations[Int(slot)])
        }
        precondition(generations.count < Int(UInt32.max), "A world holds at most \(UInt32.max) slots")
        generations.append(0)
        isLive.append(true)
        return Entity(index: UInt32(generations.count - 1), generation: 0)
    }

    @usableFromInline
    mutating func destroy(_ entity: Entity) {
        structureVersion &+= 1
        if !groups.isEmpty {
            leaveGroups(entity)
        }
        if !hooks.isEmpty {
            fireDespawnHooks(for: entity)
        }
        for slot in columns.indices {
            let held = columns.withUnsafeBufferPointer { columns in
                Unmanaged.passUnretained(columns[slot])._withUnsafeGuaranteedRef { $0.index.position(of: entity) }
            }
            guard let position = held else { continue }
            if !isKnownUniquelyReferenced(&columns[slot]) {
                copyColumn(at: slot)
            }
            columns.withUnsafeBufferPointer { columns in
                Unmanaged.passUnretained(columns[slot])._withUnsafeGuaranteedRef { $0.swapRemove($0, position) }
            }
        }
        let slot = Int(entity.index)
        isLive[slot] = false
        generations[slot] = generations[slot] == Entity.pendingGeneration - 1 ? 0 : generations[slot] + 1
        vacant.append(entity.index)
    }
}

/// The live entities of a world, lazily, in slot order.
@frozen
public struct EntitiesView: Sequence, Sendable {
    @usableFromInline let generations: [UInt32]
    @usableFromInline let isLive: [Bool]

    @inlinable
    init(generations: [UInt32], isLive: [Bool]) {
        self.generations = generations
        self.isLive = isLive
    }

    /// Steps through the live slots.
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline let generations: [UInt32]
        @usableFromInline let isLive: [Bool]
        @usableFromInline var slot = 0

        @inlinable
        init(generations: [UInt32], isLive: [Bool]) {
            self.generations = generations
            self.isLive = isLive
        }

        @inlinable
        public mutating func next() -> Entity? {
            while slot < isLive.count {
                defer { slot += 1 }
                if isLive[slot] { return Entity(index: UInt32(slot), generation: generations[slot]) }
            }
            return nil
        }
    }

    @inlinable
    public func makeIterator() -> Iterator { Iterator(generations: generations, isLive: isLive) }
}
