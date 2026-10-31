/// A component that marks an entity as a template for spawning copies.
///
/// A *prefab* is an entity that holds a ready-made set of components, such as everything a
/// goblin starts with. Spawn copies of it with ``World/spawn(from:)``, which copies every
/// component except the `Prefab` mark itself. Queries and updates skip prefabs, as they skip
/// ``Disabled`` entities, so the template never moves or takes damage along with its copies:
///
/// ```swift
/// var world = World()
/// let goblin = world.spawn(Prefab(), Name(value: "goblin"), Health(current: 10))
///
/// let first = world.spawn(from: goblin)
/// let second = world.spawn(from: goblin)
/// world[Health.self, of: second].current = 5
///
/// var names: [String] = []
/// for (_, name) in world.query(Name.self) {
///     names.append(name.value)
/// }
/// print(names)
/// // Prints "["goblin", "goblin"]"
/// print(world[Health.self, of: first].current, world[Health.self, of: second].current)
/// // Prints "10 5"
/// ```
@frozen
public struct Prefab: Component, Hashable {
    /// Creates a prefab mark.
    @inlinable
    public init() {}
}

extension World {
    /// Creates an entity holding a copy of every component of the given entity, and returns its
    /// handle.
    ///
    /// The copies are new components: they are marked added and changed at the current
    /// ``changeTick``, and they fire add and insert hooks. The entity's relations are copied
    /// along with its ``Targets`` components, so a clone of a child is the child's sibling. The
    /// entity's own children aren't cloned.
    ///
    /// ```swift
    /// var world = World()
    /// let original = world.spawn(Position(x: 1, y: 2), Velocity(dx: 0, dy: 1))
    ///
    /// let copy = world.clone(original)
    /// world[Position.self, of: copy].x = 10
    ///
    /// print(world[Position.self, of: original].x, world[Position.self, of: copy].x)
    /// // Prints "1.0 10.0"
    /// ```
    ///
    /// - Parameter entity: The entity to copy.
    /// - Returns: The handle of the new entity.
    /// - Complexity: O(*t*), where *t* is the number of component types the world has stored.
    /// - Precondition: `entity` is live. The checked spelling, ``clone(checked:)``, throws
    ///   instead.
    @discardableResult
    public mutating func clone(_ entity: Entity) -> Entity {
        precondition(contains(entity), "Cloning stale entity \(entity)")
        return copy(entity, skipping: nil)
    }

    /// Creates an entity holding a copy of every component of the given entity, and returns its
    /// handle, throwing an error if the entity isn't live.
    ///
    /// The copy is made as ``clone(_:)`` makes it.
    ///
    /// - Parameter entity: The entity to copy.
    /// - Returns: The handle of the new entity.
    /// - Throws: ``StaleEntity`` if `entity` isn't live. The world is unchanged.
    /// - Complexity: O(*t*), where *t* is the number of component types the world has stored.
    @discardableResult
    public mutating func clone(checked entity: Entity) throws(StaleEntity) -> Entity {
        guard contains(entity) else { throw StaleEntity() }
        return copy(entity, skipping: nil)
    }

    /// Creates an entity from a prefab, holding a copy of every component of the prefab except
    /// its ``Prefab`` mark, and returns its handle.
    ///
    /// The copy is made as ``clone(_:)`` makes it, without the mark, so queries and updates
    /// reach the new entity. See ``Prefab`` for an example.
    ///
    /// - Parameter prefab: The entity to copy. It doesn't need to hold a ``Prefab`` mark.
    /// - Returns: The handle of the new entity.
    /// - Complexity: O(*t*), where *t* is the number of component types the world has stored.
    /// - Precondition: `prefab` is live. The checked spelling, ``spawn(checkedFrom:)``, throws
    ///   instead.
    @discardableResult
    public mutating func spawn(from prefab: Entity) -> Entity {
        precondition(contains(prefab), "Spawning from stale entity \(prefab)")
        return copy(prefab, skipping: ObjectIdentifier(Prefab.self))
    }

    /// Creates an entity from a prefab, holding a copy of every component of the prefab except
    /// its ``Prefab`` mark, and returns its handle, throwing an error if the prefab isn't live.
    ///
    /// - Parameter prefab: The entity to copy.
    /// - Returns: The handle of the new entity.
    /// - Throws: ``StaleEntity`` if `prefab` isn't live. The world is unchanged.
    /// - Complexity: O(*t*), where *t* is the number of component types the world has stored.
    @discardableResult
    public mutating func spawn(checkedFrom prefab: Entity) throws(StaleEntity) -> Entity {
        guard contains(prefab) else { throw StaleEntity() }
        return copy(prefab, skipping: ObjectIdentifier(Prefab.self))
    }

    /// Spawns an entity holding a copy of every component of `source` except one of type
    /// `skipped`.
    mutating func copy(_ source: Entity, skipping skipped: ObjectIdentifier?) -> Entity {
        var components: [any Component] = []
        for slot in columns.indices {
            let column = columns[slot]
            guard let position = column.index.position(of: source) else { continue }
            let component = column.read(column, position)
            if let skipped, ObjectIdentifier(type(of: component)) == skipped { continue }
            components.append(component)
        }
        let entity = makeEntity()
        for component in components {
            store(component, for: entity)
        }
        endOperation()
        return entity
    }
}
