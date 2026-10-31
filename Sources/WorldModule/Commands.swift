/// A buffer of changes to a world, recorded now and applied later in the order they were
/// recorded.
///
/// While a query or an update visits a world's entities, the world can't be changed in other
/// ways: spawning or despawning an entity, or adding or removing a component, would disturb the
/// storage being visited. Record such changes in a command buffer instead, and apply them with
/// ``World/apply(_:)`` once the visit is over. The following example despawns every entity whose
/// health has run out:
///
/// ```swift
/// var world = World()
/// world.spawn(Health(current: 0))
/// world.spawn(Health(current: 10))
///
/// var commands = Commands()
/// for (entity, health) in world.query(Health.self) where health.current <= 0 {
///     commands.despawn(entity)
/// }
/// world.apply(commands)
///
/// print(world.count)
/// // Prints "1"
/// ```
///
/// A command on an entity that is no longer live when it applies does nothing, so two commands
/// that despawn the same entity are safe.
///
/// ### Naming Entities That Commands Will Spawn
///
/// ``spawn(_:)`` returns a placeholder handle for the entity it will create. Later commands in the
/// same buffer can name that placeholder, and ``World/apply(_:)`` returns the real handles of the
/// entities it spawned, in the order their commands were recorded:
///
/// ```swift
/// var world = World()
/// var commands = Commands()
/// let ship = commands.spawn(Position(x: 0, y: 0))
/// let turret = commands.spawn(Position(x: 1, y: 0))
/// commands.addChild(turret, to: ship)
///
/// let spawned = world.apply(commands)
/// print(world.parent(of: spawned[1]) == spawned[0])
/// // Prints "true"
/// ```
///
/// A placeholder stands for its entity only inside the buffer that returned it; the world holds no
/// entity with that handle.
///
/// ### Commands from Systems
///
/// A system running alongside others can't apply commands itself, because applying them would
/// change entities the other systems are reading. It queues them with ``World/queue(_:)``
/// instead, and the schedule applies every queued buffer at the end of each wave of systems.
@frozen
public struct Commands: Sendable {
    /// Each command: a change to the world, given the entities the buffer has spawned so far.
    @usableFromInline var operations: [@Sendable (inout World, inout [Entity]) -> Void] = []
    /// The number of spawn commands recorded.
    @usableFromInline var spawnCount = 0

    /// Creates an empty command buffer.
    @inlinable
    public init() {}

    /// The number of commands recorded in the buffer.
    @inlinable
    public var count: Int { operations.count }

    /// A Boolean value indicating whether the buffer holds no commands.
    @inlinable
    public var isEmpty: Bool { operations.isEmpty }

    /// Records spawning an entity holding the given components, and returns a placeholder handle
    /// for it.
    ///
    /// Commands recorded after this one in the same buffer can name the placeholder, and it
    /// resolves to the spawned entity when the buffer applies. The placeholder stands for the
    /// entity only inside this buffer: the world holds no entity with it. ``World/apply(_:)``
    /// returns the real handles of the spawned entities, in the order their commands were
    /// recorded:
    ///
    /// ```swift
    /// var world = World()
    /// var commands = Commands()
    /// let ball = commands.spawn(Position(x: 0, y: 0))
    /// commands.insert(Velocity(dx: 1, dy: 0), into: ball)
    ///
    /// let spawned = world.apply(commands)
    /// print(world.contains(Velocity.self, in: spawned[0]))
    /// // Prints "true"
    /// ```
    ///
    /// - Parameter bundles: The components and bundles the new entity holds.
    /// - Returns: A placeholder handle for the entity, valid in later commands of this buffer.
    @inlinable
    @discardableResult
    public mutating func spawn<each B: Bundle>(_ bundles: repeat each B) -> Entity {
        let pending = Entity(index: UInt32(spawnCount), generation: Entity.pendingGeneration)
        spawnCount += 1
        operations.append { world, spawned in spawned.append(world.spawn(repeat each bundles)) }
        return pending
    }

    /// Records spawning a copy of an entity, and returns a placeholder handle for the copy.
    ///
    /// When the command applies, it copies the entity as ``World/clone(_:)`` does. If `entity`
    /// isn't live then, the spawned entity holds nothing.
    ///
    /// - Parameter entity: The entity to copy, or a placeholder an earlier command in this buffer
    ///   returned.
    /// - Returns: A placeholder handle for the copy, valid in later commands of this buffer.
    @inlinable
    @discardableResult
    public mutating func clone(_ entity: Entity) -> Entity {
        let pending = Entity(index: UInt32(spawnCount), generation: Entity.pendingGeneration)
        spawnCount += 1
        operations.append { world, spawned in
            let source = Self.resolve(entity, in: spawned)
            spawned.append((try? world.clone(checked: source)) ?? world.spawn())
        }
        return pending
    }

    /// Records spawning an entity from a prefab, and returns a placeholder handle for it.
    ///
    /// When the command applies, it copies the prefab without its ``Prefab`` mark, as
    /// ``World/spawn(from:)`` does. If `prefab` isn't live then, the spawned entity holds nothing.
    ///
    /// - Parameter prefab: The prefab to copy, or a placeholder an earlier command in this buffer
    ///   returned.
    /// - Returns: A placeholder handle for the new entity, valid in later commands of this
    ///   buffer.
    @inlinable
    @discardableResult
    public mutating func spawn(from prefab: Entity) -> Entity {
        let pending = Entity(index: UInt32(spawnCount), generation: Entity.pendingGeneration)
        spawnCount += 1
        operations.append { world, spawned in
            let source = Self.resolve(prefab, in: spawned)
            spawned.append((try? world.spawn(checkedFrom: source)) ?? world.spawn())
        }
        return pending
    }

    /// `entity`, or the entity a spawn command of this buffer created if `entity` is the handle
    /// that command returned.
    @inlinable
    static func resolve(_ entity: Entity, in spawned: [Entity]) -> Entity {
        guard entity.generation == Entity.pendingGeneration, Int(entity.index) < spawned.count else {
            return entity
        }
        return spawned[Int(entity.index)]
    }

    /// Records despawning an entity, as ``World/despawn(_:)`` does.
    ///
    /// When the command applies, nothing happens if `entity` isn't live.
    ///
    /// - Parameter entity: The entity to despawn, or a placeholder an earlier command in this
    ///   buffer returned.
    @inlinable
    public mutating func despawn(_ entity: Entity) {
        operations.append { world, spawned in try? world.despawn(checked: Self.resolve(entity, in: spawned)) }
    }

    /// Records making one entity the last child of another, as ``World/addChild(_:to:)`` does.
    ///
    /// When the command applies, nothing happens if either entity isn't live, or if `parent` is
    /// `child` or one of its descendants.
    ///
    /// - Parameters:
    ///   - child: The entity to attach, or a placeholder an earlier command in this buffer
    ///     returned.
    ///   - parent: The entity to attach it to, or a placeholder an earlier command in this buffer
    ///     returned.
    @inlinable
    public mutating func addChild(_ child: Entity, to parent: Entity) {
        operations.append { world, spawned in
            try? world.addChild(Self.resolve(child, in: spawned), checkedTo: Self.resolve(parent, in: spawned))
        }
    }

    /// Records detaching an entity from its parent, as ``World/removeParent(of:)`` does.
    ///
    /// When the command applies, nothing happens if `child` isn't live.
    ///
    /// - Parameter child: The entity to detach, or a placeholder an earlier command in this buffer
    ///   returned.
    @inlinable
    public mutating func removeParent(of child: Entity) {
        operations.append { world, spawned in _ = try? world.removeParent(checkedOf: Self.resolve(child, in: spawned)) }
    }

    /// Records relating one entity to another, as ``World/relate(_:_:to:)`` does.
    ///
    /// When the command applies, nothing happens if either entity isn't live, or if relating by
    /// ``ChildOf`` would make the hierarchy cyclic.
    ///
    /// - Parameters:
    ///   - source: The entity the relation goes from, or a placeholder an earlier command in this
    ///     buffer returned.
    ///   - relation: The relation.
    ///   - target: The entity the relation goes to, or a placeholder an earlier command in this
    ///     buffer returned.
    @inlinable
    public mutating func relate<R: Relation>(_ source: Entity, _ relation: R, to target: Entity) {
        operations.append { world, spawned in
            let source = Self.resolve(source, in: spawned)
            let target = Self.resolve(target, in: spawned)
            guard !world.closesHierarchyCycle(R.self, from: source, to: target) else { return }
            try? world.relate(source, relation, checkedTo: target)
        }
    }

    /// Records removing the relation of the given type between two entities, as
    /// ``World/unrelate(_:_:from:)`` does.
    ///
    /// When the command applies, nothing happens if `source` isn't live.
    ///
    /// - Parameters:
    ///   - source: The entity the relation goes from, or a placeholder an earlier command in this
    ///     buffer returned.
    ///   - type: The type of the relation to remove.
    ///   - target: The entity the relation goes to, or a placeholder an earlier command in this
    ///     buffer returned.
    @inlinable
    public mutating func unrelate<R: Relation>(_ source: Entity, _ type: R.Type, from target: Entity) {
        operations.append { world, spawned in
            _ = try? world.unrelate(Self.resolve(source, in: spawned), R.self, checkedFrom: Self.resolve(target, in: spawned))
        }
    }

    /// Records adding the given components to an entity, replacing any it holds of the same
    /// types, as ``World/insert(_:into:)-70968`` does.
    ///
    /// When the command applies, nothing happens if `entity` isn't live.
    ///
    /// - Parameters:
    ///   - bundles: The components and bundles to add.
    ///   - entity: The entity to add them to, or a placeholder an earlier command in this buffer
    ///     returned.
    @inlinable
    public mutating func insert<each B: Bundle>(_ bundles: repeat each B, into entity: Entity) {
        operations.append { world, spawned in
            try? world.insert(repeat each bundles, checkedInto: Self.resolve(entity, in: spawned))
        }
    }

    /// Records triggering an event on an entity, as ``World/trigger(_:on:)`` does.
    ///
    /// When the command applies, nothing happens if `entity` isn't live.
    ///
    /// - Parameters:
    ///   - event: The event to trigger.
    ///   - entity: The entity to trigger it on, or a placeholder an earlier command in this buffer
    ///     returned.
    @inlinable
    public mutating func trigger<E: EntityEvent>(_ event: E, on entity: Entity) {
        operations.append { world, spawned in try? world.trigger(event, checkedOn: Self.resolve(entity, in: spawned)) }
    }

    /// Records adding a resource to the world, replacing any of the same type.
    ///
    /// - Parameter resource: The resource to add.
    @inlinable
    public mutating func insert<R: Resource>(resource: R) {
        operations.append { world, _ in world.resources.insert(resource) }
    }

    /// Records an arbitrary change to the world.
    ///
    /// Use this method for a change that no other command covers. The closure runs when the buffer
    /// applies, with the world as it is at that point:
    ///
    /// ```swift
    /// var world = World()
    /// var commands = Commands()
    /// commands.record { world in
    ///     for _ in 0..<3 { world.spawn(Health(current: 10)) }
    /// }
    /// world.apply(commands)
    ///
    /// print(world.count(of: Health.self))
    /// // Prints "3"
    /// ```
    ///
    /// - Parameter body: A closure that changes the world.
    @inlinable
    public mutating func record(_ body: @escaping @Sendable (inout World) -> Void) {
        operations.append { world, _ in body(&world) }
    }
}

extension World {
    /// Applies the commands of a buffer in the order they were recorded.
    ///
    /// Commands on entities that are no longer live do nothing. See ``Commands`` for examples.
    ///
    /// - Parameter commands: The commands to apply.
    /// - Returns: The entities the buffer's spawn commands created, in the order the commands were
    ///   recorded.
    /// - Complexity: The sum of the costs of the commands.
    @inlinable
    @discardableResult
    public mutating func apply(_ commands: Commands) -> [Entity] {
        var spawned: [Entity] = []
        spawned.reserveCapacity(commands.spawnCount)
        for operation in commands.operations {
            operation(&self, &spawned)
        }
        return spawned
    }
}

extension World {
    /// Adds a command buffer to the world's queue, to apply later with
    /// ``applyQueuedCommands()``.
    ///
    /// A system that runs alongside others queues the commands it records rather than applying
    /// them, because applying them would change entities the other systems are reading. A
    /// schedule applies every queued buffer at the end of each wave of systems it runs together:
    ///
    /// ```swift
    /// var world = World()
    /// var commands = Commands()
    /// commands.spawn(Position(x: 0, y: 0))
    ///
    /// world.queue(commands)
    /// print(world.count, world.hasQueuedCommands)
    /// // Prints "0 true"
    ///
    /// world.applyQueuedCommands()
    /// print(world.count, world.hasQueuedCommands)
    /// // Prints "1 false"
    /// ```
    ///
    /// - Parameter commands: The commands to queue.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func queue(_ commands: Commands) {
        queuedCommands.append(commands)
    }

    /// A Boolean value indicating whether any command buffers are waiting in the world's queue.
    @inlinable
    public var hasQueuedCommands: Bool { !queuedCommands.isEmpty }

    /// Applies every queued command buffer, in the order the buffers were queued, and empties the
    /// queue.
    ///
    /// Buffers that the applied commands queue in turn are applied too, before this method
    /// returns.
    ///
    /// - Returns: The entities the buffers' spawn commands created, in the order the commands were
    ///   recorded.
    /// - Complexity: The sum of the costs of the commands.
    @inlinable
    @discardableResult
    public mutating func applyQueuedCommands() -> [Entity] {
        var spawned: [Entity] = []
        while !queuedCommands.isEmpty {
            let queued = queuedCommands
            queuedCommands = []
            for commands in queued {
                spawned += apply(commands)
            }
        }
        return spawned
    }
}
