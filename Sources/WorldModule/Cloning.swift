/// Marks an entity as a template to spawn copies of with ``World/spawn(from:)``: queries and
/// updates skip it, as they skip ``Disabled`` entities.
///
/// ```swift
/// let goblin = world.spawn(Prefab(), Health(current: 10), Name("goblin"))
/// let first = world.spawn(from: goblin)   // Health(current: 10), Name("goblin")
/// ```
@frozen
public struct Prefab: Component, Hashable {
    @inlinable
    public init() {}
}

extension World {
    /// Spawns an entity holding a copy of every component `entity` holds, and returns its handle.
    ///
    /// The copies are new components: added and changed at the current ``changeTick``, firing
    /// add and insert hooks. Its relations are copied with its ``Targets`` components, so a
    /// clone of a child is its sibling; the entity's own children are not cloned.
    ///
    /// - Complexity: O(*t*) for *t* component types the world has stored.
    /// - Precondition: `entity` is live. Use ``clone(checked:)`` to throw instead.
    @discardableResult
    public mutating func clone(_ entity: Entity) -> Entity {
        precondition(contains(entity), "Cloning stale entity \(entity)")
        return copy(entity, skipping: nil)
    }

    /// Spawns an entity holding a copy of every component `entity` holds, and returns its handle.
    ///
    /// - Complexity: O(*t*) for *t* component types the world has stored.
    /// - Throws: ``StaleEntity`` when `entity` is not live; the world is unchanged.
    @discardableResult
    public mutating func clone(checked entity: Entity) throws(StaleEntity) -> Entity {
        guard contains(entity) else { throw StaleEntity() }
        return copy(entity, skipping: nil)
    }

    /// Spawns an entity holding a copy of every component `prefab` holds but ``Prefab``, and
    /// returns its handle; see ``clone(_:)``.
    ///
    /// - Complexity: O(*t*) for *t* component types the world has stored.
    /// - Precondition: `prefab` is live. Use ``spawn(checkedFrom:)`` to throw instead.
    @discardableResult
    public mutating func spawn(from prefab: Entity) -> Entity {
        precondition(contains(prefab), "Spawning from stale entity \(prefab)")
        return copy(prefab, skipping: ObjectIdentifier(Prefab.self))
    }

    /// Spawns an entity holding a copy of every component `prefab` holds but ``Prefab``, and
    /// returns its handle.
    ///
    /// - Complexity: O(*t*) for *t* component types the world has stored.
    /// - Throws: ``StaleEntity`` when `prefab` is not live; the world is unchanged.
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
