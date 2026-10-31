/// The parent and children of every entity in a world, indexed by slot.
@usableFromInline
struct Hierarchy: Sendable {
    /// Each slot's parent, or nil; shorter than the slots when the last ones have none.
    @usableFromInline var parents: [Entity?] = []
    /// Each slot's children in the order they were added; shorter than the slots when the last
    /// ones have none.
    @usableFromInline var children: [[Entity]] = []
    /// The number of parent links.
    @usableFromInline var links = 0

    @usableFromInline
    init() {}

    @inlinable
    func parent(of entity: Entity) -> Entity? {
        let slot = Int(entity.index)
        return slot < parents.count ? parents[slot] : nil
    }

    @inlinable
    func children(of entity: Entity) -> [Entity] {
        let slot = Int(entity.index)
        return slot < children.count ? children[slot] : []
    }

    /// Makes `child` the last child of `parent`, detaching it from its current parent first.
    @usableFromInline
    mutating func link(_ child: Entity, to parent: Entity) {
        unlink(child)
        let childSlot = Int(child.index)
        let parentSlot = Int(parent.index)
        if parents.count <= childSlot {
            parents.append(contentsOf: repeatElement(nil, count: childSlot + 1 - parents.count))
        }
        if children.count <= parentSlot {
            children.append(contentsOf: repeatElement([], count: parentSlot + 1 - children.count))
        }
        parents[childSlot] = parent
        children[parentSlot].append(child)
        links += 1
    }

    /// Detaches `child` from its parent, returning the parent.
    @usableFromInline
    @discardableResult
    mutating func unlink(_ child: Entity) -> Entity? {
        guard let parent = parent(of: child) else { return nil }
        parents[Int(child.index)] = nil
        let parentSlot = Int(parent.index)
        if let position = children[parentSlot].firstIndex(of: child) {
            children[parentSlot].remove(at: position)
        }
        links -= 1
        return parent
    }

    /// Whether `ancestor` is `entity` or one of its ancestors.
    @usableFromInline
    func isAncestor(_ ancestor: Entity, ofOrIs entity: Entity) -> Bool {
        var current: Entity? = entity
        while let walking = current {
            if walking == ancestor { return true }
            current = parent(of: walking)
        }
        return false
    }

    /// `entity` and its descendants, depth-first, each before its children.
    @usableFromInline
    func subtree(of entity: Entity) -> [Entity] {
        var result: [Entity] = []
        var stack = [entity]
        while let next = stack.popLast() {
            result.append(next)
            stack.append(contentsOf: children(of: next).reversed())
        }
        return result
    }

    /// Forgets the links of `entity`, which is being despawned with all its descendants.
    @usableFromInline
    mutating func forget(_ entity: Entity) {
        let slot = Int(entity.index)
        if slot < parents.count, parents[slot] != nil {
            parents[slot] = nil
            links -= 1
        }
        if slot < children.count {
            children[slot] = []
        }
    }
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
        guard !hierarchy.isAncestor(child, ofOrIs: parent) else { throw CyclicHierarchy() }
        hierarchy.link(child, to: parent)
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
        guard !hierarchy.isAncestor(child, ofOrIs: parent) else { throw .cyclicHierarchy }
        hierarchy.link(child, to: parent)
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
        return hierarchy.unlink(child)
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
        return hierarchy.unlink(child)
    }

    /// The parent of `entity`, or nil if it has none or is not live.
    ///
    /// - Complexity: O(1).
    @inlinable
    public func parent(of entity: Entity) -> Entity? {
        contains(entity) ? hierarchy.parent(of: entity) : nil
    }

    /// The children of `entity` in the order they were added; empty if it has none or is not
    /// live.
    ///
    /// - Complexity: O(1).
    @inlinable
    public func children(of entity: Entity) -> [Entity] {
        contains(entity) ? hierarchy.children(of: entity) : []
    }

    /// The ancestors of `entity`, its parent first and its root last; empty if it has no parent
    /// or is not live.
    ///
    /// - Complexity: O(1); each step of the walk is O(1).
    @inlinable
    public func ancestors(of entity: Entity) -> AncestorsView {
        AncestorsView(hierarchy: hierarchy, first: parent(of: entity))
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
        DescendantsView(hierarchy: hierarchy, roots: children(of: entity))
    }

    /// Despawns `entity` and its descendants, detaching it from its parent.
    @usableFromInline
    @inline(never)
    mutating func destroySubtree(_ entity: Entity) {
        hierarchy.unlink(entity)
        for member in hierarchy.subtree(of: entity) {
            hierarchy.forget(member)
            destroy(member)
        }
    }
}

/// The ancestors of an entity, its parent first, lazily.
@frozen
public struct AncestorsView: Sequence, Sendable {
    @usableFromInline let hierarchy: Hierarchy
    @usableFromInline let first: Entity?

    @inlinable
    init(hierarchy: Hierarchy, first: Entity?) {
        self.hierarchy = hierarchy
        self.first = first
    }

    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(hierarchy: hierarchy, next: first)
    }

    /// Walks from an entity's parent to its root.
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline let hierarchy: Hierarchy
        @usableFromInline var upcoming: Entity?

        @inlinable
        init(hierarchy: Hierarchy, next: Entity?) {
            self.hierarchy = hierarchy
            upcoming = next
        }

        @inlinable
        public mutating func next() -> Entity? {
            guard let current = upcoming else { return nil }
            upcoming = hierarchy.parent(of: current)
            return current
        }
    }
}

/// The descendants of an entity, depth-first with each before its own children, lazily.
@frozen
public struct DescendantsView: Sequence, Sendable {
    @usableFromInline let hierarchy: Hierarchy
    @usableFromInline let roots: [Entity]

    @inlinable
    init(hierarchy: Hierarchy, roots: [Entity]) {
        self.hierarchy = hierarchy
        self.roots = roots
    }

    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(hierarchy: hierarchy, stack: roots.reversed())
    }

    /// Walks a subtree depth-first.
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline let hierarchy: Hierarchy
        /// Entities still to visit, the next last.
        @usableFromInline var stack: [Entity]

        @inlinable
        init(hierarchy: Hierarchy, stack: [Entity]) {
            self.hierarchy = hierarchy
            self.stack = stack
        }

        @inlinable
        public mutating func next() -> Entity? {
            guard let current = stack.popLast() else { return nil }
            stack.append(contentsOf: hierarchy.children(of: current).reversed())
            return current
        }
    }
}
