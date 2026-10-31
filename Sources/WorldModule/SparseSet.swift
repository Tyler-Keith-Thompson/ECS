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
        if slot >= sparse.count {
            sparse.append(contentsOf: repeatElement(0, count: slot - sparse.count + 1))
        }
        dense.append(entity)
        ticks.append(ComponentTicks(added: tick, changed: tick))
        sparse[slot] = UInt32(dense.count)
        return dense.count - 1
    }

    /// Swaps the entities, and their ticks, at positions `first` and `second`.
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
@usableFromInline
class AnyColumn: @unchecked Sendable {
    @exclusivity(unchecked) @usableFromInline final var index: SparseIndex
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
    @usableFromInline final var group = -1
    /// Whether the column holds a relation's ``Targets``, which the world indexes by target.
    @usableFromInline final let isRelation: Bool
    /// Whether the world keeps an index of the column's values (``World/index(_:)``).
    @usableFromInline final var isIndexed = false
    /// Counts the times the column was reached for writing, so an index of its values knows
    /// whether a write may have changed one.
    @usableFromInline final var writeVersion: UInt64 = 0

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
