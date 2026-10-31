/// A kind of link from one entity, the source, to others, its targets: a pair of the relation and
/// a target.
///
/// A source holds its pairs of a relation in a ``Targets`` component, so queries find sources
/// with `.with(Targets<Likes>.self)` and read their targets as a term; the world also indexes
/// each target's sources, so `.related(Likes.self, to: bob)` visits only those.
///
/// ```swift
/// struct Likes: Relation {}
/// world.relate(alice, Likes(), to: bob)
/// world.targets(Likes.self, of: alice)  // [bob]
/// world.sources(Likes.self, of: bob)    // [alice]
/// ```
///
/// A relation's value is stored with each pair, so relations can carry data
/// (`struct Owes: Relation { var amount: Int }`).
public protocol Relation: Sendable {
    /// Whether a source relates to at most one target: relating it to another replaces the first.
    /// False by default.
    static var isExclusive: Bool { get }

    /// What despawning a target does to the sources related to it: ``CleanupAction/remove`` (the
    /// default) removes their pairs with it, ``CleanupAction/despawn`` despawns them too.
    static var onTargetDespawn: CleanupAction { get }
}

extension Relation {
    /// Not exclusive.
    @inlinable
    public static var isExclusive: Bool { false }

    /// ``CleanupAction/remove``.
    @inlinable
    public static var onTargetDespawn: CleanupAction { .remove }
}

/// What despawning a relation's target does to the sources related to it.
@frozen
public enum CleanupAction: Hashable, Sendable {
    /// Removes the sources' pairs with the target.
    case remove
    /// Despawns the sources, and in turn what despawning them cleans up.
    case despawn
}

/// The targets a source relates to by `R`, with the relation's value for each, in the order they
/// were related.
///
/// The world keeps this component: ``World/relate(_:_:to:)`` and ``World/unrelate(_:_:from:)``
/// change it, and despawning a target removes its pair. Read it like any component, in a query or
/// with the world's subscript.
@frozen
public struct Targets<R: Relation>: Component {
    @usableFromInline var storedEntities: [Entity]
    @usableFromInline var storedRelations: [R]

    /// The targets, in the order they were related.
    @inlinable
    public var entities: [Entity] { storedEntities }

    /// The relation's value for each target, at the same positions as ``entities``.
    @inlinable
    public var relations: [R] { storedRelations }

    @inlinable
    init(entities: [Entity], relations: [R]) {
        storedEntities = entities
        storedRelations = relations
    }

    /// The number of targets.
    @inlinable
    public var count: Int { entities.count }

    /// The relation's value for `target`, or nil if the source does not relate to it.
    ///
    /// - Complexity: O(*k*) for *k* targets.
    @inlinable
    public subscript(target: Entity) -> R? {
        entities.firstIndex(of: target).map { relations[$0] }
    }
}

extension Targets: Equatable where R: Equatable {}
extension Targets: Hashable where R: Hashable {}
extension Targets: Codable where R: Codable {
    @usableFromInline
    enum CodingKeys: String, CodingKey {
        case storedEntities = "entities"
        case storedRelations = "relations"
    }
}

/// A ``Targets`` component of any relation, for code that does not know the relation.
@usableFromInline
protocol AnyTargets {
    /// The targets.
    var targetEntities: [Entity] { get }
    /// A fresh index of the relation's sources by target.
    static func makeIndex() -> RelationIndex
}

extension Targets: AnyTargets {
    @inlinable
    var targetEntities: [Entity] { entities }

    @inlinable
    static func makeIndex() -> RelationIndex {
        RelationIndex(key: ObjectIdentifier(Targets<R>.self), onTargetDespawn: R.onTargetDespawn) { world, source, target in
            world.removeTarget(R.self, target, from: source)
        }
    }
}

/// One relation's pairs by target: the sources related to each entity, and the targets each
/// source was last seen relating to, so a change to a source's ``Targets`` can be applied as a
/// difference.
@usableFromInline
struct RelationIndex: Sendable {
    /// The identifier of the relation's ``Targets`` type.
    @usableFromInline let key: ObjectIdentifier
    @usableFromInline let onTargetDespawn: CleanupAction
    /// Removes the pair of a source and a target, through the world, so the source's
    /// ``Targets`` changes too.
    @usableFromInline let removeTarget: @Sendable (inout World, _ source: Entity, _ target: Entity) -> Void
    /// Each slot's targets as a source; shorter than the slots when the last ones have none.
    @usableFromInline var targetsBySource: [[Entity]] = []
    /// Each slot's sources as a target, in the order they were related; shorter than the slots
    /// when the last ones have none.
    @usableFromInline var sourcesByTarget: [[Entity]] = []

    @inlinable
    init(key: ObjectIdentifier, onTargetDespawn: CleanupAction, removeTarget: @escaping @Sendable (inout World, Entity, Entity) -> Void) {
        self.key = key
        self.onTargetDespawn = onTargetDespawn
        self.removeTarget = removeTarget
    }

    @inlinable
    func sources(of target: Entity) -> [Entity] {
        let slot = Int(target.index)
        return slot < sourcesByTarget.count ? sourcesByTarget[slot] : []
    }

    /// Records that `source` now relates to exactly `targets`.
    @usableFromInline
    mutating func setTargets(_ targets: [Entity], of source: Entity) {
        let slot = Int(source.index)
        let old = slot < targetsBySource.count ? targetsBySource[slot] : []
        guard old != targets else { return }
        for target in old where !targets.contains(target) {
            let targetSlot = Int(target.index)
            if let position = sourcesByTarget[targetSlot].firstIndex(of: source) {
                sourcesByTarget[targetSlot].remove(at: position)
            }
        }
        for target in targets where !old.contains(target) {
            let targetSlot = Int(target.index)
            if sourcesByTarget.count <= targetSlot {
                sourcesByTarget.append(contentsOf: repeatElement([], count: targetSlot + 1 - sourcesByTarget.count))
            }
            sourcesByTarget[targetSlot].append(source)
        }
        if targetsBySource.count <= slot {
            targetsBySource.append(contentsOf: repeatElement([], count: slot + 1 - targetsBySource.count))
        }
        targetsBySource[slot] = targets
    }

    /// Forgets `target`'s sources, returning them.
    @usableFromInline
    mutating func takeSources(of target: Entity) -> [Entity] {
        let slot = Int(target.index)
        guard slot < sourcesByTarget.count else { return [] }
        defer { sourcesByTarget[slot] = [] }
        return sourcesByTarget[slot]
    }
}

extension World {
    // MARK: Relations

    /// Takes from `part`, a part of this world, the relation indexes of the ``Targets`` types
    /// among `types`, which it wrote.
    @usableFromInline
    mutating func takeRelationIndexes(of types: some Sequence<ObjectIdentifier>, from part: World) {
        guard !part.relationIndexes.isEmpty else { return }
        for type in types {
            guard let index = part.relationIndexes.first(where: { $0.key == type }) else { continue }
            if let position = relationIndexes.firstIndex(where: { $0.key == type }) {
                relationIndexes[position] = index
            } else {
                relationIndexes.append(index)
            }
        }
    }

    /// Relates `source` to `target` by `relation`, replacing the value of a pair it already has.
    ///
    /// For an exclusive relation (``Relation/isExclusive``), the source's other pair is removed.
    ///
    /// ```swift
    /// world.relate(alice, Likes(), to: bob)
    /// ```
    ///
    /// - Complexity: O(*k*) for *k* targets of `source` and sources of the targets it gains or
    ///   loses.
    /// - Precondition: Both entities are live. Use ``relate(_:_:checkedTo:)`` to throw instead.
    @inlinable
    public mutating func relate<R: Relation>(_ source: Entity, _ relation: R, to target: Entity) {
        precondition(contains(source), "Relating stale entity \(source)")
        precondition(contains(target), "Relating to stale entity \(target)")
        storeRelation(relation, from: source, to: target)
        endOperation()
    }

    /// Relates `source` to `target` by `relation`; see ``relate(_:_:to:)``.
    ///
    /// - Throws: ``StaleEntity`` when either entity is not live; the world is unchanged.
    @inlinable
    public mutating func relate<R: Relation>(_ source: Entity, _ relation: R, checkedTo target: Entity) throws(StaleEntity) {
        guard contains(source), contains(target) else { throw StaleEntity() }
        storeRelation(relation, from: source, to: target)
        endOperation()
    }

    /// Removes the pair of `source` and `target` by `R`, returning its value, or nil if there
    /// was none. A source left with no targets loses its ``Targets`` component.
    ///
    /// - Complexity: O(*k*) for *k* targets of `source` and sources of `target`.
    /// - Precondition: `source` is live. Use ``unrelate(_:_:checkedFrom:)`` to throw instead.
    @inlinable
    @discardableResult
    public mutating func unrelate<R: Relation>(_ source: Entity, _ type: R.Type, from target: Entity) -> R? {
        precondition(contains(source), "Unrelating stale entity \(source)")
        let removed = removeTarget(R.self, target, from: source)
        endOperation()
        return removed
    }

    /// Removes the pair of `source` and `target` by `R`; see ``unrelate(_:_:from:)``.
    ///
    /// - Throws: ``StaleEntity`` when `source` is not live; the world is unchanged.
    @inlinable
    @discardableResult
    public mutating func unrelate<R: Relation>(_ source: Entity, _ type: R.Type, checkedFrom target: Entity) throws(StaleEntity) -> R? {
        guard contains(source) else { throw StaleEntity() }
        let removed = removeTarget(R.self, target, from: source)
        endOperation()
        return removed
    }

    /// The entities `source` relates to by `R`, in the order they were related; empty for a
    /// stale entity.
    ///
    /// - Complexity: O(1).
    @inlinable
    public func targets<R: Relation>(_ type: R.Type, of source: Entity) -> [Entity] {
        (try? self[checked: Targets<R>.self, of: source])?.entities ?? []
    }

    /// The entities related to `target` by `R`, in the order they were related; empty for a
    /// stale entity.
    ///
    /// - Complexity: O(*r*) for *r* relations the world has stored.
    @inlinable
    public func sources<R: Relation>(_ type: R.Type, of target: Entity) -> [Entity] {
        guard contains(target) else { return [] }
        let key = ObjectIdentifier(Targets<R>.self)
        return relationIndexes.first { $0.key == key }?.sources(of: target) ?? []
    }

    @inlinable
    mutating func storeRelation<R: Relation>(_ relation: R, from source: Entity, to target: Entity) {
        var targets = (try? self[checked: Targets<R>.self, of: source]) ?? Targets(entities: [], relations: [])
        if let position = targets.entities.firstIndex(of: target) {
            targets.storedRelations[position] = relation
        } else if R.isExclusive {
            targets = Targets(entities: [target], relations: [relation])
        } else {
            targets.storedEntities.append(target)
            targets.storedRelations.append(relation)
        }
        store(targets, for: source)
    }

    /// Removes the pair of `source` and `target`, without ending the operation.
    @usableFromInline
    @discardableResult
    mutating func removeTarget<R: Relation>(_ type: R.Type, _ target: Entity, from source: Entity) -> R? {
        guard var targets = try? self[checked: Targets<R>.self, of: source],
              let position = targets.entities.firstIndex(of: target) else { return nil }
        let removed = targets.relations[position]
        targets.storedEntities.remove(at: position)
        targets.storedRelations.remove(at: position)
        if targets.entities.isEmpty {
            _ = discard(Targets<R>.self, from: source)
        } else {
            store(targets, for: source)
        }
        return removed
    }

    /// Brings the relation index of `C`, a ``Targets`` type, up to date with `entity`'s
    /// component, which was just stored or removed.
    @usableFromInline
    @inline(never)
    mutating func reindexTargets<C: Component>(_ type: C.Type, of entity: Entity) {
        let key = ObjectIdentifier(C.self)
        let position: Int
        if let found = relationIndexes.firstIndex(where: { $0.key == key }) {
            position = found
        } else {
            relationIndexes.append((C.self as! any AnyTargets.Type).makeIndex())
            position = relationIndexes.count - 1
        }
        let targets = (try? self[checked: C.self, of: entity]).map { ($0 as! any AnyTargets).targetEntities } ?? []
        relationIndexes[position].setTargets(targets, of: entity)
    }

    /// Removes `entity`, which is being despawned, from every relation, and applies each
    /// relation's cleanup to the sources related to it: removing their pairs, or adding them to
    /// `cascade` to despawn.
    @usableFromInline
    @inline(never)
    mutating func releaseRelations(of entity: Entity, cascade: inout [Entity]) {
        for position in relationIndexes.indices {
            relationIndexes[position].setTargets([], of: entity)
            let sources = relationIndexes[position].takeSources(of: entity)
            let removeTarget = relationIndexes[position].removeTarget
            for source in sources where source != entity && contains(source) {
                switch relationIndexes[position].onTargetDespawn {
                case .remove:
                    removeTarget(&self, source, entity)
                case .despawn:
                    cascade.append(source)
                }
            }
        }
    }
}
