/// A type that describes a kind of link from one entity to others.
///
/// A relation links a *source* entity to one or more *target* entities: a unit likes another,
/// a turret is aimed at a ship, a part is a child of its parent (``ChildOf``). Declare a relation
/// as a type that conforms to `Relation`, then link entities with ``World/relate(_:_:to:)``:
///
/// ```swift
/// struct Likes: Relation {}
///
/// var world = World()
/// let alice = world.spawn(Name(value: "Alice"))
/// let bob = world.spawn(Name(value: "Bob"))
/// world.relate(alice, Likes(), to: bob)
///
/// print(world.targets(Likes.self, of: alice) == [bob])
/// // Prints "true"
/// print(world.sources(Likes.self, of: bob) == [alice])
/// // Prints "true"
/// ```
///
/// The world stores each link as a pair of a target and a value of the relation, so a relation
/// can carry data about the link:
///
/// ```swift
/// struct Owes: Relation { var amount: Int }
///
/// var world = World()
/// let alice = world.spawn(Name(value: "Alice"))
/// let bob = world.spawn(Name(value: "Bob"))
/// world.relate(alice, Owes(amount: 20), to: bob)
///
/// if let debt = world[Targets<Owes>.self, of: alice][bob] {
///     print(debt.amount)
///     // Prints "20"
/// }
/// ```
///
/// ### Querying Relations
///
/// A source holds its pairs of a relation in a ``Targets`` component, so you can read and filter
/// on it like any other component. The world also keeps an index of each target's sources, so
/// filtering a query with `.related(_:to:)` visits only the entities related to that target:
///
/// ```swift
/// var world = World()
/// let alice = world.spawn(Name(value: "Alice"))
/// let bob = world.spawn(Name(value: "Bob"))
/// let carol = world.spawn(Name(value: "Carol"))
/// world.relate(alice, Likes(), to: bob)
/// world.relate(carol, Likes(), to: bob)
///
/// let fans = world.query(Name.self).related(Likes.self, to: bob).map { $0.1.value }
/// print(fans.sorted())
/// // Prints "["Alice", "Carol"]"
/// ```
///
/// ### Customizing a Relation
///
/// By default a source can relate to any number of targets, and despawning a target removes
/// its pairs from the sources. Implement ``isExclusive`` or ``onTargetDespawn`` to change that.
public protocol Relation: Sendable {
    /// A Boolean value indicating whether a source relates to at most one target.
    ///
    /// When this is `true`, relating a source to a new target replaces its previous one. The
    /// default implementation returns `false`.
    static var isExclusive: Bool { get }

    /// What despawning a target does to the sources related to it.
    ///
    /// The default implementation returns ``CleanupAction/remove``, which removes the sources'
    /// pairs with the target. Return ``CleanupAction/despawn`` to despawn the sources along with
    /// the target, as ``ChildOf`` does.
    static var onTargetDespawn: CleanupAction { get }
}

extension Relation {
    /// A Boolean value indicating whether a source relates to at most one target; by default,
    /// `false`.
    @inlinable
    public static var isExclusive: Bool { false }

    /// What despawning a target does to the sources related to it; by default,
    /// ``CleanupAction/remove``.
    @inlinable
    public static var onTargetDespawn: CleanupAction { .remove }
}

/// What despawning a relation's target does to the sources related to it.
///
/// A relation chooses its cleanup with ``Relation/onTargetDespawn``. The following example
/// declares a relation whose sources are despawned with their target:
///
/// ```swift
/// struct Orbits: Relation {
///     static var isExclusive: Bool { true }
///     static var onTargetDespawn: CleanupAction { .despawn }
/// }
///
/// var world = World()
/// let planet = world.spawn(Name(value: "Planet"))
/// let moon = world.spawn(Name(value: "Moon"))
/// world.relate(moon, Orbits(), to: planet)
///
/// world.despawn(planet)
/// print(world.contains(moon))
/// // Prints "false"
/// ```
@frozen
public enum CleanupAction: Hashable, Sendable {
    /// Removes the sources' pairs with the target, keeping the sources.
    case remove
    /// Despawns the sources, which in turn cleans up whatever is related to them.
    case despawn
}

/// The component that holds a source entity's targets of a relation, with the relation's value
/// for each.
///
/// The world maintains this component for you: ``World/relate(_:_:to:)`` and
/// ``World/unrelate(_:_:from:)`` change it, and despawning a target removes its pair. A source
/// with no targets of `R` holds no `Targets<R>`. Read it like any other component, with the
/// world's subscript or as a query term:
///
/// ```swift
/// var world = World()
/// let alice = world.spawn(Name(value: "Alice"))
/// let bob = world.spawn(Name(value: "Bob"))
/// let carol = world.spawn(Name(value: "Carol"))
/// world.relate(alice, Owes(amount: 20), to: bob)
/// world.relate(alice, Owes(amount: 5), to: carol)
///
/// let debts = world[Targets<Owes>.self, of: alice]
/// print(debts.count)
/// // Prints "2"
/// print(debts.relations.map(\.amount))
/// // Prints "[20, 5]"
/// ```
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

    /// Accesses the relation's value for the given target.
    ///
    /// - Parameter target: A target of the source.
    /// - Returns: The relation's value for `target`, or `nil` if the source doesn't relate to it.
    /// - Complexity: O(*k*), where *k* is the number of targets.
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
    func targets(of source: Entity) -> [Entity] {
        let slot = Int(source.index)
        return slot < targetsBySource.count ? targetsBySource[slot] : []
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

    /// Links a source entity to a target entity by a relation.
    ///
    /// The pair is added to the end of the source's targets of `R`. If the source already relates
    /// to `target` by `R`, this method replaces the pair's value instead. For an exclusive
    /// relation (``Relation/isExclusive``), the new pair replaces the source's previous one.
    ///
    /// ```swift
    /// var world = World()
    /// let alice = world.spawn(Name(value: "Alice"))
    /// let bob = world.spawn(Name(value: "Bob"))
    ///
    /// world.relate(alice, Owes(amount: 20), to: bob)
    /// world.relate(alice, Owes(amount: 35), to: bob)
    /// print(world[Targets<Owes>.self, of: alice].relations.map(\.amount))
    /// // Prints "[35]"
    /// ```
    ///
    /// - Parameters:
    ///   - source: The entity the link starts from.
    ///   - relation: The relation's value for the pair.
    ///   - target: The entity the link points to.
    /// - Precondition: Both entities are live. The checked spelling,
    ///   ``relate(_:_:checkedTo:)``, throws instead. Relating by ``ChildOf`` must not make the
    ///   hierarchy cyclic; ``addChild(_:to:)`` throws ``CyclicHierarchy`` instead.
    /// - Complexity: O(*k*), where *k* is the number of targets of `source` plus the number of
    ///   sources of each target it gains or loses.
    @inlinable
    public mutating func relate<R: Relation>(_ source: Entity, _ relation: R, to target: Entity) {
        precondition(contains(source), "Relating stale entity \(source)")
        precondition(contains(target), "Relating to stale entity \(target)")
        precondition(!closesHierarchyCycle(R.self, from: source, to: target), "Relating \(source) by ChildOf to \(target) would make the hierarchy cyclic; addChild(_:checkedTo:) throws instead")
        storeRelation(relation, from: source, to: target)
        endOperation()
    }

    /// Links a source entity to a target entity by a relation, throwing if either entity is
    /// stale.
    ///
    /// This method behaves like ``relate(_:_:to:)``, but reports a stale entity as an error
    /// rather than trapping.
    ///
    /// - Parameters:
    ///   - source: The entity the link starts from.
    ///   - relation: The relation's value for the pair.
    ///   - target: The entity the link points to.
    /// - Throws: ``StaleEntity`` if either entity isn't live. The world is unchanged.
    /// - Precondition: Relating by ``ChildOf`` doesn't make the hierarchy cyclic;
    ///   ``addChild(_:checkedTo:)`` throws instead.
    /// - Complexity: O(*k*), where *k* is the number of targets of `source` plus the number of
    ///   sources of each target it gains or loses.
    @inlinable
    public mutating func relate<R: Relation>(_ source: Entity, _ relation: R, checkedTo target: Entity) throws(StaleEntity) {
        guard contains(source), contains(target) else { throw StaleEntity() }
        precondition(!closesHierarchyCycle(R.self, from: source, to: target), "Relating \(source) by ChildOf to \(target) would make the hierarchy cyclic; addChild(_:checkedTo:) throws instead")
        storeRelation(relation, from: source, to: target)
        endOperation()
    }

    /// Removes the link between a source entity and a target entity and returns its value.
    ///
    /// A source left with no targets of `R` loses its ``Targets`` component.
    ///
    /// ```swift
    /// var world = World()
    /// let alice = world.spawn(Name(value: "Alice"))
    /// let bob = world.spawn(Name(value: "Bob"))
    /// world.relate(alice, Owes(amount: 20), to: bob)
    ///
    /// if let settled = world.unrelate(alice, Owes.self, from: bob) {
    ///     print(settled.amount)
    ///     // Prints "20"
    /// }
    /// print(world.contains(Targets<Owes>.self, in: alice))
    /// // Prints "false"
    /// ```
    ///
    /// - Parameters:
    ///   - source: The entity the link starts from.
    ///   - type: The relation type.
    ///   - target: The entity the link points to.
    /// - Returns: The relation's value for the pair, or `nil` if `source` didn't relate to
    ///   `target`.
    /// - Precondition: `source` is live. The checked spelling, ``unrelate(_:_:checkedFrom:)``,
    ///   throws instead.
    /// - Complexity: O(*k*), where *k* is the number of targets of `source` plus the number of
    ///   sources of `target`.
    @inlinable
    @discardableResult
    public mutating func unrelate<R: Relation>(_ source: Entity, _ type: R.Type, from target: Entity) -> R? {
        precondition(contains(source), "Unrelating stale entity \(source)")
        let removed = removeTarget(R.self, target, from: source)
        endOperation()
        return removed
    }

    /// Removes the link between a source entity and a target entity and returns its value,
    /// throwing if the source is stale.
    ///
    /// This method behaves like ``unrelate(_:_:from:)``, but reports a stale source as an error
    /// rather than trapping.
    ///
    /// - Parameters:
    ///   - source: The entity the link starts from.
    ///   - type: The relation type.
    ///   - target: The entity the link points to.
    /// - Returns: The relation's value for the pair, or `nil` if `source` didn't relate to
    ///   `target`.
    /// - Throws: ``StaleEntity`` if `source` isn't live. The world is unchanged.
    /// - Complexity: O(*k*), where *k* is the number of targets of `source` plus the number of
    ///   sources of `target`.
    @inlinable
    @discardableResult
    public mutating func unrelate<R: Relation>(_ source: Entity, _ type: R.Type, checkedFrom target: Entity) throws(StaleEntity) -> R? {
        guard contains(source) else { throw StaleEntity() }
        let removed = removeTarget(R.self, target, from: source)
        endOperation()
        return removed
    }

    /// Returns the entities a source relates to by a relation, in the order they were related.
    ///
    /// - Parameters:
    ///   - type: The relation type.
    ///   - source: The entity the links start from.
    /// - Returns: The targets of `source`, or an empty array if it has none or isn't live.
    /// - Complexity: O(1).
    @inlinable
    public func targets<R: Relation>(_ type: R.Type, of source: Entity) -> [Entity] {
        (try? self[checked: Targets<R>.self, of: source])?.entities ?? []
    }

    /// Returns the entities that relate to a target by a relation, in the order they were
    /// related.
    ///
    /// - Parameters:
    ///   - type: The relation type.
    ///   - target: The entity the links point to.
    /// - Returns: The sources related to `target`, or an empty array if it has none or isn't
    ///   live.
    /// - Complexity: O(*r*), where *r* is the number of relation types the world has stored.
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
            var despawned: [Entity] = []
            for source in sources where source != entity && contains(source) {
                switch relationIndexes[position].onTargetDespawn {
                case .remove:
                    removeTarget(&self, source, entity)
                case .despawn:
                    despawned.append(source)
                }
            }
            // Reversed, so the first source is despawned next: a parent's children in order,
            // each before its own.
            cascade.append(contentsOf: despawned.reversed())
        }
    }
}
