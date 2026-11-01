/// Which entities a column holds, and where: a sparse array from slot to position, and the dense
/// array of entities at those positions, with the tick each component was added and last changed.
///
/// Lookup, insertion and removal are O(1); removal moves the last entity into the vacated
/// position, so the dense order is the order of insertion with swaps on removal.
@frozen
@usableFromInline
struct SparseIndex: Sendable {
    /// Position + 1 of each slot's entity in `dense`, or 0 for none.
    @usableFromInline var sparse: [UInt32] = []
    @usableFromInline var dense: [Entity] = []
    /// When each entity's component was added and last changed, parallel to `dense`.
    @usableFromInline var ticks: [ComponentTicks] = []

    @inlinable
    init() {}

    /// The position of `entity` in `dense`, or nil if the column does not hold it.
    @inlinable
    @inline(__always)
    func position(of entity: Entity) -> Int? {
        let slot = Int(entity.index)
        guard slot < sparse.count else { return nil }
        let stored = sparse[slot]
        guard stored != 0 else { return nil }
        let position = Int(stored &- 1)
        return dense[position] == entity ? position : nil
    }

    /// Appends `entity`, which the column must not hold, added and changed at `tick`, and returns
    /// its position.
    @inlinable
    mutating func append(_ entity: Entity, at tick: ChangeTick) -> Int {
        let slot = Int(entity.index)
        if slot == sparse.count {
            // Spawning appends slots in order, and appending one element is much cheaper than
            // appending a repeated sequence of one.
            sparse.append(0)
        } else if slot > sparse.count {
            sparse.append(contentsOf: repeatElement(0, count: slot - sparse.count + 1))
        }
        dense.append(entity)
        ticks.append(ComponentTicks(added: tick, changed: tick))
        sparse[slot] = UInt32(dense.count)
        return dense.count - 1
    }

    /// Swaps the entities, and their ticks, at positions `first` and `second`.
    /// Appends `entities`, none of which the column holds, all added and changed at `tick`.
    @inlinable
    mutating func append(contentsOf entities: [Entity], at tick: ChangeTick) {
        guard let highest = entities.lazy.map(\.index).max() else { return }
        if Int(highest) >= sparse.count {
            sparse.append(contentsOf: repeatElement(0, count: Int(highest) + 1 - sparse.count))
        }
        let first = dense.count
        dense.append(contentsOf: entities)
        ticks.append(contentsOf: repeatElement(ComponentTicks(added: tick, changed: tick), count: entities.count))
        sparse.withUnsafeMutableBufferPointer { sparse in
            for (offset, entity) in entities.enumerated() {
                sparse[Int(entity.index)] = UInt32(first + offset + 1)
            }
        }
    }

    @inlinable
    mutating func swapAt(_ first: Int, _ second: Int) {
        guard first != second else { return }
        dense.swapAt(first, second)
        ticks.swapAt(first, second)
        sparse[Int(dense[first].index)] = UInt32(first + 1)
        sparse[Int(dense[second].index)] = UInt32(second + 1)
    }

    /// Removes the entity at `position`, moving the last entity into its place.
    @inlinable
    mutating func swapRemove(at position: Int) {
        let removed = dense[position]
        let last = dense.removeLast()
        let lastTicks = ticks.removeLast()
        if position < dense.count {
            dense[position] = last
            ticks[position] = lastTicks
            sparse[Int(last.index)] = UInt32(position + 1)
        }
        sparse[Int(removed.index)] = 0
    }
}

/// When a component was added and when it was last changed.
@frozen
@usableFromInline
struct ComponentTicks: Sendable {
    @usableFromInline var added: ChangeTick
    @usableFromInline var changed: ChangeTick

    @inlinable
    init(added: ChangeTick, changed: ChangeTick) {
        self.added = added
        self.changed = changed
    }
}

/// The components of one type, whatever the type is: what a ``World`` does to a column without
/// knowing its component type.
///
/// Columns are shared between copies of a world and copied before the first write to a shared
/// one, so they are only ever mutated through a unique reference; that is why their storage needs
/// no exclusivity checks.
/// The entities whose component of a column's type was added or changed, each with the tick of
/// the change, in the order of the changes, so that the ones changed since a tick are found
/// without walking the column.
///
/// An entity can appear more than once, and entries for entities that have since lost the
/// component stay until the log is compacted; readers check each entity against the column.
@frozen
@usableFromInline
struct ChangeLog: Sendable {
    @usableFromInline var ticks: [ChangeTick] = []
    @usableFromInline var entities: [Entity] = []
    /// Whether every entry's tick is at least the previous one's, so a search can find the
    /// entries after a tick.
    @usableFromInline var isOrdered = true

    @inlinable
    init() {}

    /// A log of every component of a column, in the order they last changed.
    @inlinable
    init(of index: SparseIndex) {
        let order = index.dense.indices.sorted { (index.ticks[$0].changed, index.dense[$0]) < (index.ticks[$1].changed, index.dense[$1]) }
        ticks = order.map { index.ticks[$0].changed }
        entities = order.map { index.dense[$0] }
    }

    @inlinable
    mutating func record(_ entity: Entity, at tick: ChangeTick) {
        if let last = ticks.last, tick < last { isOrdered = false }
        ticks.append(tick)
        entities.append(entity)
    }

    /// Records the entities among the first `end` of `visited` whose component a visit just
    /// changed at `tick`, read through the column's `index` and `ticks`.
    @inlinable
    mutating func record(changesOf visited: [Entity], upTo end: Int, at tick: ChangeTick, index: SparseIndex, ticks columnTicks: [ComponentTicks]) {
        for entity in visited[..<end] {
            guard let position = index.position(of: entity), columnTicks[position].changed == tick else { continue }
            record(entity, at: tick)
        }
        compactIfLarge(index: index, ticks: columnTicks)
    }

    /// The entities recorded as changed after `tick`, each once.
    ///
    /// - Complexity: O(log *m* + *k*) for *m* entries, *k* of them after `tick`.
    @inlinable
    func entities(changedAfter tick: ChangeTick) -> [Entity] {
        var first = 0
        if isOrdered {
            var upper = ticks.count
            while first < upper {
                let middle = (first + upper) / 2
                if ticks[middle] > tick { upper = middle } else { first = middle + 1 }
            }
        }
        var seen = Set<Entity>(minimumCapacity: ticks.count - first)
        var found: [Entity] = []
        for position in first ..< ticks.count where ticks[position] > tick && seen.insert(entities[position]).inserted {
            found.append(entities[position])
        }
        return found
    }

    /// Drops the entries a later one supersedes, and those of entities that lost the component,
    /// once the log holds more than twice as many entries as the column holds components.
    ///
    /// - Complexity: O(*m*) for *m* entries when it compacts, which happens at most once per
    ///   *n* records for a column of *n* components.
    @inlinable
    mutating func compactIfLarge(index: SparseIndex, ticks columnTicks: [ComponentTicks]) {
        guard ticks.count > 2 * index.dense.count + 64 else { return }
        var keptTicks: [ChangeTick] = []
        var keptEntities: [Entity] = []
        var seen = Set<Entity>(minimumCapacity: index.dense.count)
        for position in ticks.indices.reversed() {
            let entity = entities[position]
            guard let held = index.position(of: entity), columnTicks[held].changed == ticks[position],
                  seen.insert(entity).inserted else { continue }
            keptTicks.append(ticks[position])
            keptEntities.append(entity)
        }
        ticks = keptTicks.reversed()
        entities = keptEntities.reversed()
        isOrdered = zip(ticks, ticks.dropFirst()).allSatisfy { $0 <= $1 }
    }
}

@usableFromInline
class AnyColumn: @unchecked Sendable {
    @exclusivity(unchecked) @usableFromInline final var index: SparseIndex
    /// The log of changes to the column's components, kept once the world tracks the type's
    /// changes (`trackChanges(of:)`).
    @exclusivity(unchecked) @usableFromInline final var changeLog: ChangeLog?
    /// Removes the entity and component at a position, moving the last ones into its place.
    ///
    /// A closure made where the component type is known, so that a world removing from a column
    /// it knows only as `AnyColumn` (when despawning) runs code specialized for the type rather
    /// than the generic class's unspecialized methods.
    @usableFromInline final let swapRemove: @Sendable (AnyColumn, Int) -> Void
    /// Swaps the entities and components at two positions; a closure for the same reason.
    @usableFromInline final let swapAt: @Sendable (AnyColumn, Int, Int) -> Void
    /// The component at a position; a closure for the same reason.
    @usableFromInline final let read: @Sendable (AnyColumn, Int) -> any Component
    /// The position in its world's groups of the group that owns the column, or -1 for none.
    @exclusivity(unchecked) @usableFromInline final var group = -1
    /// Whether the column holds a relation's ``Targets``, which the world indexes by target.
    @usableFromInline final let isRelation: Bool
    /// Whether the world keeps an index of the column's values (``World/index(_:)-u1gw``).
    @exclusivity(unchecked) @usableFromInline final var isIndexed = false
    /// Counts the times the column was reached for writing, so an index of its values knows
    /// whether a write may have changed one.
    @exclusivity(unchecked) @usableFromInline final var writeVersion: UInt64 = 0

    @inlinable
    init(
        index: SparseIndex,
        swapRemove: @escaping @Sendable (AnyColumn, Int) -> Void,
        swapAt: @escaping @Sendable (AnyColumn, Int, Int) -> Void,
        read: @escaping @Sendable (AnyColumn, Int) -> any Component,
        isRelation: Bool
    ) {
        self.index = index
        self.swapRemove = swapRemove
        self.swapAt = swapAt
        self.read = read
        self.isRelation = isRelation
    }

    /// A column holding the same entities and components.
    /// Records that `entity`'s component changed at `tick`, when the column keeps a change log.
    @inlinable
    @inline(__always)
    final func logChange(of entity: Entity, at tick: ChangeTick) {
        guard changeLog != nil else { return }
        logChangeSlowly(of: entity, at: tick)
    }

    @usableFromInline
    @inline(never)
    final func logChangeSlowly(of entity: Entity, at tick: ChangeTick) {
        changeLog!.record(entity, at: tick)
        changeLog!.compactIfLarge(index: index, ticks: index.ticks)
    }

    /// The entities a visit is walking and how many of them, held while a column that logs its
    /// changes is visited, so the log can record them afterward.
    @exclusivity(unchecked) @usableFromInline final var visiting: (entities: [Entity], end: Int)?

    /// Records the entities of the visit just finished whose component it changed at `tick`,
    /// read through `ticks`, the column's ticks moved out for the visit.
    @usableFromInline
    @inline(never)
    final func logVisit(at tick: ChangeTick, ticks: [ComponentTicks]) {
        guard let (entities, end) = visiting else { return }
        visiting = nil
        changeLog!.record(changesOf: entities, upTo: end, at: tick, index: index, ticks: ticks)
    }

    @usableFromInline
    func copy() -> AnyColumn { preconditionFailure("abstract") }

    /// An empty column of the same component type.
    @usableFromInline
    func makeEmpty() -> AnyColumn { preconditionFailure("abstract") }
}

/// The `C` components of a world, densely packed, in the order of their column's index.
@usableFromInline
final class Column<C: Component>: AnyColumn, @unchecked Sendable {
    @exclusivity(unchecked) @usableFromInline var values: [C]

    @inlinable
    init() {
        values = []
        super.init(
            index: SparseIndex(),
            swapRemove: { column, position in unsafeDowncast(column, to: Column<C>.self).swapRemove(at: position) },
            swapAt: { column, first, second in unsafeDowncast(column, to: Column<C>.self).swapAt(first, second) },
            read: { column, position in unsafeDowncast(column, to: Column<C>.self).values[position] },
            isRelation: C.self is any AnyTargets.Type
        )
    }

    @inlinable
    init(copying column: Column<C>) {
        values = column.values
        super.init(index: column.index, swapRemove: column.swapRemove, swapAt: column.swapAt, read: column.read, isRelation: column.isRelation)
        group = column.group
        isIndexed = column.isIndexed
        writeVersion = column.writeVersion
        changeLog = column.changeLog
    }

    /// Swaps the entities and components at `first` and `second`.
    @inlinable
    func swapAt(_ first: Int, _ second: Int) {
        index.swapAt(first, second)
        values.swapAt(first, second)
    }

    @inlinable
    override func copy() -> AnyColumn { Column(copying: self) }

    @inlinable
    override func makeEmpty() -> AnyColumn { Column() }

    /// Removes the entity and component at `position`, moving the last ones into its place.
    @inlinable
    func swapRemove(at position: Int) {
        index.swapRemove(at: position)
        let last = values.removeLast()
        if position < values.count { values[position] = last }
    }

    /// The column's contents, as values that later writes to the column do not change.
    @inlinable
    var snapshot: ColumnSnapshot<C> { ColumnSnapshot(index: index, values: values) }
}

/// A column's index and components at one moment.
@frozen
@usableFromInline
struct ColumnSnapshot<C: Component>: Sendable {
    @usableFromInline let index: SparseIndex
    @usableFromInline let values: [C]

    @inlinable
    init(index: SparseIndex = SparseIndex(), values: [C] = []) {
        self.index = index
        self.values = values
    }

    /// The component of `entity`, which the column must hold, read directly at `cursor` when
    /// this column is the one being walked (`column == driverColumn`). Counts `column` up by one,
    /// so a pack of snapshots can be read in one expansion.
    @inlinable
    @inline(__always)
    func value(of entity: Entity, cursor: Int, driverColumn: Int, column: inout Int) -> C {
        defer { column += 1 }
        return column == driverColumn || driverColumn == alignedDriver ? values[cursor] : values[index.position(of: entity)!]
    }
}
