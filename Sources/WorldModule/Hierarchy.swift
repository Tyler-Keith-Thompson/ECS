/// The relation of a child to its parent: exclusive, and despawning a parent despawns its
/// children.
///
/// ``World/addChild(_:to:)`` relates a child to its parent, refusing cycles; queries find
/// children with `.related(ChildOf.self, to: parent)`, entities with a parent with
/// `.with(Targets<ChildOf>.self)` and roots with `.without(Targets<ChildOf>.self)`.
@frozen
public struct ChildOf: Relation, Hashable, Codable {
    /// Exclusive: an entity has at most one parent.
    @inlinable
    public static var isExclusive: Bool { true }

    /// ``CleanupAction/despawn``: despawning a parent despawns its children.
    @inlinable
    public static var onTargetDespawn: CleanupAction { .despawn }

    @inlinable
    public init() {}
}

/// The error ``World/addChild(_:to:)`` throws when the parent is the child or one of its
/// descendants, so the link would close a cycle.
@frozen
public struct CyclicHierarchy: Error, Hashable, Sendable {
    @inlinable
    public init() {}
}

/// The error ``World/addChild(_:checkedTo:)`` throws: one case per way the change can fail.
@frozen
public enum HierarchyError: Error, Hashable, Sendable {
    /// The child or the parent was despawned or never spawned by the world.
    case staleEntity
    /// The parent is the child or one of its descendants.
    case cyclicHierarchy
}

extension World {
    // MARK: Hierarchy

    /// Makes `child` the last child of `parent`, moving it from its current parent if it has
    /// one.
    ///
    /// Despawning an entity despawns its descendants with it.
    ///
    /// ```swift
    /// let ship = world.spawn(Position(x: 0, y: 0))
    /// let turret = world.spawn(Position(x: 1, y: 0))
    /// try world.addChild(turret, to: ship)
    /// ```
    ///
    /// - Complexity: O(*d* + *k*) for *d* ancestors of `parent` and *k* children of the child's
    ///   current parent.
    /// - Throws: ``CyclicHierarchy`` when `parent` is `child` or one of its descendants; the
    ///   world is unchanged.
    /// - Precondition: Both entities are live. Use ``addChild(_:checkedTo:)`` to throw instead.
    @inlinable
    public mutating func addChild(_ child: Entity, to parent: Entity) throws(CyclicHierarchy) {
        precondition(contains(child), "Adding stale child \(child)")
        precondition(contains(parent), "Adding a child to stale parent \(parent)")
        guard !isAncestor(child, ofOrIs: parent) else { throw CyclicHierarchy() }
        link(child, to: parent)
        endOperation()
    }

    /// Makes `child` the last child of `parent`, moving it from its current parent if it has
    /// one.
    ///
    /// - Complexity: O(*d* + *k*) for *d* ancestors of `parent` and *k* children of the child's
    ///   current parent.
    /// - Throws: ``HierarchyError/staleEntity`` when either entity is not live, and
    ///   ``HierarchyError/cyclicHierarchy`` when `parent` is `child` or one of its descendants;
    ///   the world is unchanged.
    @inlinable
    public mutating func addChild(_ child: Entity, checkedTo parent: Entity) throws(HierarchyError) {
        guard contains(child), contains(parent) else { throw .staleEntity }
        guard !isAncestor(child, ofOrIs: parent) else { throw .cyclicHierarchy }
        link(child, to: parent)
        endOperation()
    }

    /// Detaches `child` from its parent, keeping both entities, and returns the parent, or nil
    /// if it had none.
    ///
    /// - Complexity: O(*k*) for *k* children of the parent.
    /// - Precondition: `child` is live. Use ``removeParent(checkedOf:)`` to throw instead.
    @inlinable
    @discardableResult
    public mutating func removeParent(of child: Entity) -> Entity? {
        precondition(contains(child), "Removing the parent of stale entity \(child)")
        let parent = unlink(child)
        endOperation()
        return parent
    }

    /// Detaches `child` from its parent, keeping both entities, and returns the parent, or nil
    /// if it had none.
    ///
    /// - Complexity: O(*k*) for *k* children of the parent.
    /// - Throws: ``StaleEntity`` when `child` is not live; the world is unchanged.
    @inlinable
    @discardableResult
    public mutating func removeParent(checkedOf child: Entity) throws(StaleEntity) -> Entity? {
        guard contains(child) else { throw StaleEntity() }
        let parent = unlink(child)
        endOperation()
        return parent
    }

    /// The parent of `entity`, or nil if it has none or is not live.
    ///
    /// - Complexity: O(1).
    @inlinable
    public func parent(of entity: Entity) -> Entity? {
        (try? self[checked: Targets<ChildOf>.self, of: entity])?.entities.first
    }

    /// The children of `entity` in the order they were added; empty if it has none or is not
    /// live.
    ///
    /// - Complexity: O(*r*) for *r* relations the world has stored.
    @inlinable
    public func children(of entity: Entity) -> [Entity] {
        sources(ChildOf.self, of: entity)
    }

    /// The ancestors of `entity`, its parent first and its root last; empty if it has no parent
    /// or is not live.
    ///
    /// - Complexity: O(1); each step of the walk is O(1).
    @inlinable
    public func ancestors(of entity: Entity) -> AncestorsView {
        AncestorsView(index: childOfIndex, first: parent(of: entity))
    }

    /// The descendants of `entity`, depth-first, each before its own children and children in
    /// the order they were added; empty if it has no children or is not live.
    ///
    /// ```swift
    /// for part in world.descendants(of: ship) {
    ///     world[Position.self, of: part].x += 1
    /// }
    /// ```
    ///
    /// - Complexity: O(1); the walk is O(*n*) for *n* descendants.
    @inlinable
    public func descendants(of entity: Entity) -> DescendantsView {
        DescendantsView(index: childOfIndex, roots: children(of: entity))
    }

    /// The index of the ``ChildOf`` relation, empty if no entity has had a parent.
    @inlinable
    var childOfIndex: RelationIndex {
        let key = ObjectIdentifier(Targets<ChildOf>.self)
        return relationIndexes.first { $0.key == key } ?? Targets<ChildOf>.makeIndex()
    }

    /// Whether `ancestor` is `entity` or one of its ancestors.
    @inlinable
    func isAncestor(_ ancestor: Entity, ofOrIs entity: Entity) -> Bool {
        let index = childOfIndex
        var current: Entity? = entity
        while let walking = current {
            if walking == ancestor { return true }
            current = index.targets(of: walking).first
        }
        return false
    }

    /// Makes `child` the last child of `parent`, without ending the operation.
    @inlinable
    mutating func link(_ child: Entity, to parent: Entity) {
        if let current = self.parent(of: child) {
            removeTarget(ChildOf.self, current, from: child)
        }
        storeRelation(ChildOf(), from: child, to: parent)
    }

    /// Detaches `child` from its parent, returning the parent, without ending the operation.
    @inlinable
    mutating func unlink(_ child: Entity) -> Entity? {
        guard let parent = parent(of: child) else { return nil }
        removeTarget(ChildOf.self, parent, from: child)
        return parent
    }
}

/// The ancestors of an entity, its parent first, lazily.
@frozen
public struct AncestorsView: Sequence, Sendable {
    @usableFromInline let index: RelationIndex
    @usableFromInline let first: Entity?

    @inlinable
    init(index: RelationIndex, first: Entity?) {
        self.index = index
        self.first = first
    }

    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(index: index, next: first)
    }

    /// Walks from an entity's parent to its root.
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline let index: RelationIndex
        @usableFromInline var upcoming: Entity?

        @inlinable
        init(index: RelationIndex, next: Entity?) {
            self.index = index
            upcoming = next
        }

        @inlinable
        public mutating func next() -> Entity? {
            guard let current = upcoming else { return nil }
            upcoming = index.targets(of: current).first
            return current
        }
    }
}

/// The descendants of an entity, depth-first with each before its own children, lazily.
@frozen
public struct DescendantsView: Sequence, Sendable {
    @usableFromInline let index: RelationIndex
    @usableFromInline let roots: [Entity]

    @inlinable
    init(index: RelationIndex, roots: [Entity]) {
        self.index = index
        self.roots = roots
    }

    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(index: index, stack: roots.reversed())
    }

    /// Walks a subtree depth-first.
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline let index: RelationIndex
        /// Entities still to visit, the next last.
        @usableFromInline var stack: [Entity]

        @inlinable
        init(index: RelationIndex, stack: [Entity]) {
            self.index = index
            self.stack = stack
        }

        @inlinable
        public mutating func next() -> Entity? {
            guard let current = stack.popLast() else { return nil }
            stack.append(contentsOf: index.sources(of: current).reversed())
            return current
        }
    }
}
