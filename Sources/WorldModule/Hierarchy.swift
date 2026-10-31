/// The relation that links a child entity to its parent.
///
/// A hierarchy groups entities into trees: a ship and its turrets, a menu and its buttons. Each
/// entity has at most one parent, and despawning a parent despawns its children, and theirs in
/// turn. Build a hierarchy with ``World/addChild(_:to:)``, which refuses a link that would make
/// an entity its own ancestor, and walk it with ``World/parent(of:)``,
/// ``World/children(of:)``, ``World/ancestors(of:)`` and ``World/descendants(of:)``.
///
/// The following example attaches a turret and an engine to a ship, then despawns the ship,
/// which takes its parts with it:
///
/// ```swift
/// var world = World()
/// let ship = world.spawn(Name(value: "Ship"))
/// let turret = world.spawn(Name(value: "Turret"))
/// let engine = world.spawn(Name(value: "Engine"))
/// try world.addChild(turret, to: ship)
/// try world.addChild(engine, to: ship)
///
/// let parts = world.children(of: ship).map { world[Name.self, of: $0].value }
/// print(parts)
/// // Prints "["Turret", "Engine"]"
///
/// world.despawn(ship)
/// print(world.contains(engine))
/// // Prints "false"
/// ```
///
/// `ChildOf` is a ``Relation`` like any other, so an entity with a parent holds a
/// `Targets<ChildOf>` component naming it. Queries use that to find the entities at each level
/// of a tree:
///
/// - `.related(ChildOf.self, to: parent)` keeps the children of `parent`.
/// - `.with(Targets<ChildOf>.self)` keeps entities that have a parent.
/// - `.without(Targets<ChildOf>.self)` keeps the roots.
///
/// ```swift
/// var world = World()
/// let menu = world.spawn(Name(value: "Menu"))
/// let play = world.spawn(Name(value: "Play"))
/// let quit = world.spawn(Name(value: "Quit"))
/// try world.addChild(play, to: menu)
/// try world.addChild(quit, to: menu)
///
/// print(world.query(Name.self).related(ChildOf.self, to: menu).count)
/// // Prints "2"
/// print(world.query(Name.self).without(Targets<ChildOf>.self).count)
/// // Prints "1"
/// ```
@frozen
public struct ChildOf: Relation, Hashable, Codable {
    /// A Boolean value indicating whether an entity has at most one parent; always `true`.
    @inlinable
    public static var isExclusive: Bool { true }

    /// What despawning a parent does to its children: ``CleanupAction/despawn``, which despawns
    /// them too.
    @inlinable
    public static var onTargetDespawn: CleanupAction { .despawn }

    /// Creates the relation's value, which carries no data.
    @inlinable
    public init() {}
}

/// An error that indicates a link would make an entity its own ancestor.
///
/// ``World/addChild(_:to:)`` throws this error when the new parent is the child itself or one of
/// the child's descendants, and leaves the world unchanged:
///
/// ```swift
/// var world = World()
/// let ship = world.spawn(Name(value: "Ship"))
/// let turret = world.spawn(Name(value: "Turret"))
/// try world.addChild(turret, to: ship)
///
/// do {
///     try world.addChild(ship, to: turret)
/// } catch {
///     print(error)
///     // Prints "CyclicHierarchy()"
/// }
/// ```
@frozen
public struct CyclicHierarchy: Error, Hashable, Sendable {
    /// Creates the error.
    @inlinable
    public init() {}
}

/// An error that indicates why ``World/addChild(_:checkedTo:)`` could not link two entities.
@frozen
public enum HierarchyError: Error, Hashable, Sendable {
    /// The child or the parent has been despawned, or was never spawned by the world.
    case staleEntity
    /// The parent is the child itself or one of its descendants.
    case cyclicHierarchy
}

extension World {
    // MARK: Hierarchy

    /// Adds an entity to the end of another entity's children.
    ///
    /// Use this method to build a hierarchy (see ``ChildOf``). If `child` already has a parent,
    /// it moves to `parent`, taking its own descendants with it. Once linked, despawning
    /// `parent` despawns `child` too.
    ///
    /// The following example attaches a turret to a ship, then moves it to a second ship:
    ///
    /// ```swift
    /// var world = World()
    /// let flagship = world.spawn(Name(value: "Flagship"))
    /// let escort = world.spawn(Name(value: "Escort"))
    /// let turret = world.spawn(Name(value: "Turret"))
    ///
    /// try world.addChild(turret, to: flagship)
    /// try world.addChild(turret, to: escort)
    /// print(world.children(of: flagship).isEmpty)
    /// // Prints "true"
    /// print(world.parent(of: turret) == escort)
    /// // Prints "true"
    /// ```
    ///
    /// - Parameters:
    ///   - child: The entity to link.
    ///   - parent: The entity to make its parent.
    /// - Throws: ``CyclicHierarchy`` if `parent` is `child` or one of its descendants. The world
    ///   is unchanged.
    /// - Precondition: Both entities are live. The checked spelling,
    ///   ``addChild(_:checkedTo:)``, throws instead.
    /// - Complexity: O(*d* + *k*), where *d* is the number of ancestors of `parent` and *k* is
    ///   the number of children of the child's current parent.
    @inlinable
    public mutating func addChild(_ child: Entity, to parent: Entity) throws(CyclicHierarchy) {
        precondition(contains(child), "Adding stale child \(child)")
        precondition(contains(parent), "Adding a child to stale parent \(parent)")
        guard !isAncestor(child, ofOrIs: parent) else { throw CyclicHierarchy() }
        link(child, to: parent)
        endOperation()
    }

    /// Adds an entity to the end of another entity's children, throwing if either entity is
    /// stale.
    ///
    /// This method behaves like ``addChild(_:to:)``, but reports a stale entity as an error
    /// rather than trapping:
    ///
    /// ```swift
    /// var world = World()
    /// let ship = world.spawn(Name(value: "Ship"))
    /// let wreck = world.spawn(Name(value: "Wreck"))
    /// world.despawn(wreck)
    ///
    /// do {
    ///     try world.addChild(wreck, checkedTo: ship)
    /// } catch {
    ///     print(error)
    ///     // Prints "staleEntity"
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - child: The entity to link.
    ///   - parent: The entity to make its parent.
    /// - Throws: ``HierarchyError/staleEntity`` if either entity isn't live, or
    ///   ``HierarchyError/cyclicHierarchy`` if `parent` is `child` or one of its descendants.
    ///   The world is unchanged.
    /// - Complexity: O(*d* + *k*), where *d* is the number of ancestors of `parent` and *k* is
    ///   the number of children of the child's current parent.
    @inlinable
    public mutating func addChild(_ child: Entity, checkedTo parent: Entity) throws(HierarchyError) {
        guard contains(child), contains(parent) else { throw .staleEntity }
        guard !isAncestor(child, ofOrIs: parent) else { throw .cyclicHierarchy }
        link(child, to: parent)
        endOperation()
    }

    /// Detaches an entity from its parent and returns the parent.
    ///
    /// Both entities stay in the world; `child` becomes a root and is no longer despawned with
    /// its former parent.
    ///
    /// ```swift
    /// var world = World()
    /// let ship = world.spawn(Name(value: "Ship"))
    /// let lifeboat = world.spawn(Name(value: "Lifeboat"))
    /// try world.addChild(lifeboat, to: ship)
    ///
    /// world.removeParent(of: lifeboat)
    /// world.despawn(ship)
    /// print(world.contains(lifeboat))
    /// // Prints "true"
    /// ```
    ///
    /// - Parameter child: The entity to detach.
    /// - Returns: The parent `child` had, or `nil` if it had none.
    /// - Precondition: `child` is live. The checked spelling, ``removeParent(checkedOf:)``,
    ///   throws instead.
    /// - Complexity: O(*k*), where *k* is the number of children of the parent.
    @inlinable
    @discardableResult
    public mutating func removeParent(of child: Entity) -> Entity? {
        precondition(contains(child), "Removing the parent of stale entity \(child)")
        let parent = unlink(child)
        endOperation()
        return parent
    }

    /// Detaches an entity from its parent and returns the parent, throwing if the entity is
    /// stale.
    ///
    /// This method behaves like ``removeParent(of:)``, but reports a stale entity as an error
    /// rather than trapping.
    ///
    /// - Parameter child: The entity to detach.
    /// - Returns: The parent `child` had, or `nil` if it had none.
    /// - Throws: ``StaleEntity`` if `child` isn't live. The world is unchanged.
    /// - Complexity: O(*k*), where *k* is the number of children of the parent.
    @inlinable
    @discardableResult
    public mutating func removeParent(checkedOf child: Entity) throws(StaleEntity) -> Entity? {
        guard contains(child) else { throw StaleEntity() }
        let parent = unlink(child)
        endOperation()
        return parent
    }

    /// Returns the parent of an entity.
    ///
    /// - Parameter entity: The entity whose parent to find.
    /// - Returns: The parent of `entity`, or `nil` if it has none or isn't live.
    /// - Complexity: O(1).
    @inlinable
    public func parent(of entity: Entity) -> Entity? {
        (try? self[checked: Targets<ChildOf>.self, of: entity])?.entities.first
    }

    /// Returns the children of an entity, in the order they were added.
    ///
    /// - Parameter entity: The entity whose children to list.
    /// - Returns: The children of `entity`, or an empty array if it has none or isn't live.
    /// - Complexity: O(*r*), where *r* is the number of relation types the world has stored.
    @inlinable
    public func children(of entity: Entity) -> [Entity] {
        sources(ChildOf.self, of: entity)
    }

    /// Returns the ancestors of an entity, from its parent up to the root of its tree.
    ///
    /// The view walks the hierarchy lazily as you iterate it. The following example finds the
    /// root that a gun belongs to:
    ///
    /// ```swift
    /// var world = World()
    /// let ship = world.spawn(Name(value: "Ship"))
    /// let turret = world.spawn(Name(value: "Turret"))
    /// let gun = world.spawn(Name(value: "Gun"))
    /// try world.addChild(turret, to: ship)
    /// try world.addChild(gun, to: turret)
    ///
    /// let chain = world.ancestors(of: gun).map { world[Name.self, of: $0].value }
    /// print(chain)
    /// // Prints "["Turret", "Ship"]"
    /// ```
    ///
    /// - Parameter entity: The entity whose ancestors to walk.
    /// - Returns: A view of the ancestors of `entity`, its parent first and its root last; empty
    ///   if it has no parent or isn't live.
    /// - Complexity: O(1). Each step of the walk is O(1).
    @inlinable
    public func ancestors(of entity: Entity) -> AncestorsView {
        AncestorsView(index: childOfIndex, first: parent(of: entity))
    }

    /// Returns the descendants of an entity, depth-first.
    ///
    /// The view visits each descendant before its own children, and siblings in the order they
    /// were added. It reads the world as it was when you called this method, so you can change
    /// the world while iterating. The following example moves a ship's parts along with it:
    ///
    /// ```swift
    /// var world = World()
    /// let ship = world.spawn(Position(x: 0, y: 0))
    /// let turret = world.spawn(Position(x: 1, y: 0))
    /// let gun = world.spawn(Position(x: 2, y: 0))
    /// try world.addChild(turret, to: ship)
    /// try world.addChild(gun, to: turret)
    ///
    /// for part in world.descendants(of: ship) {
    ///     world[Position.self, of: part].x += 10
    /// }
    /// print(world[Position.self, of: gun])
    /// // Prints "Position(x: 12.0, y: 0.0)"
    /// ```
    ///
    /// - Parameter entity: The entity whose descendants to walk.
    /// - Returns: A view of the descendants of `entity`; empty if it has no children or isn't
    ///   live.
    /// - Complexity: O(1). Walking the view is O(*n*), where *n* is the number of descendants.
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

    /// Whether relating `source` to `target` by `R` would make the hierarchy cyclic: `R` is
    /// ``ChildOf`` and `source` is `target` or one of its ancestors.
    @inlinable
    func closesHierarchyCycle<R: Relation>(_ relation: R.Type, from source: Entity, to target: Entity) -> Bool {
        R.self == ChildOf.self && isAncestor(source, ofOrIs: target)
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

/// A lazy sequence of an entity's ancestors, from its parent up to the root of its tree.
///
/// You get a view of ancestors from ``World/ancestors(of:)``.
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

    /// An iterator over an entity's ancestors, from its parent up to its root.
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

/// A lazy sequence of an entity's descendants, depth-first.
///
/// You get a view of descendants from ``World/descendants(of:)``. It visits each descendant
/// before its own children, and siblings in the order they were added.
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

    /// An iterator over an entity's descendants, depth-first.
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
