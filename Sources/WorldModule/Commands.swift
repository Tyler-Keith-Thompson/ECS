/// Changes to a world, recorded now and applied later in the order they were recorded.
///
/// Record commands while a world cannot be changed directly, such as inside
/// ``World/update(_:reading:where:body:)``, then ``World/apply(_:)`` them.
///
/// ```swift
/// var commands = Commands()
/// world.update(Health.self) { health, row in
///     if health.current <= 0 { commands.despawn(row.entity) }
/// }
/// world.apply(commands)
/// ```
///
/// A command on an entity that is no longer live when it is applied does nothing, so two
/// commands despawning one entity are safe.
///
/// ``spawn(_:)`` returns a handle to the entity it will create, which later commands in the same
/// buffer can name:
///
/// ```swift
/// var commands = Commands()
/// let ship = commands.spawn(Position(x: 0, y: 0))
/// let turret = commands.spawn(Position(x: 1, y: 0))
/// commands.addChild(turret, to: ship)
/// let spawned = world.apply(commands)  // [ship's entity, turret's entity]
/// ```
@frozen
public struct Commands: Sendable {
    /// Each command: a change to the world, given the entities the buffer has spawned so far.
    @usableFromInline var operations: [@Sendable (inout World, inout [Entity]) -> Void] = []
    /// The number of spawn commands recorded.
    @usableFromInline var spawnCount = 0

    /// No commands.
    @inlinable
    public init() {}

    /// The number of commands recorded.
    @inlinable
    public var count: Int { operations.count }

    /// Whether no commands are recorded.
    @inlinable
    public var isEmpty: Bool { operations.isEmpty }

    /// Records spawning an entity holding the components of `bundles`, and returns a handle to it that the
    /// commands recorded after this one in this buffer can name.
    ///
    /// The handle stands for the entity only inside this buffer: the world holds no entity with
    /// it, and ``World/apply(_:)`` returns the entities it spawned, in the order they were
    /// recorded.
    @inlinable
    @discardableResult
    public mutating func spawn<each B: Bundle>(_ bundles: repeat each B) -> Entity {
        let pending = Entity(index: UInt32(spawnCount), generation: Entity.pendingGeneration)
        spawnCount += 1
        operations.append { world, spawned in spawned.append(world.spawn(repeat each bundles)) }
        return pending
    }

    /// Records spawning a copy of `entity` (``World/clone(_:)``), and returns a handle to it that
    /// the commands recorded after this one in this buffer can name. If `entity` is not live
    /// when the command applies, the spawned entity holds nothing.
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

    /// Records spawning a copy of `prefab` without its ``Prefab`` mark
    /// (``World/spawn(from:)``), and returns a handle to it that the commands recorded after
    /// this one in this buffer can name. If `prefab` is not live when the command applies, the
    /// spawned entity holds nothing.
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

    /// Records despawning `entity`.
    @inlinable
    public mutating func despawn(_ entity: Entity) {
        operations.append { world, spawned in try? world.despawn(checked: Self.resolve(entity, in: spawned)) }
    }

    /// Records making `child` the last child of `parent`. When it applies, nothing happens if
    /// either entity is not live or `parent` is `child` or one of its descendants.
    @inlinable
    public mutating func addChild(_ child: Entity, to parent: Entity) {
        operations.append { world, spawned in
            try? world.addChild(Self.resolve(child, in: spawned), checkedTo: Self.resolve(parent, in: spawned))
        }
    }

    /// Records detaching `child` from its parent. When it applies, nothing happens if `child` is
    /// not live.
    @inlinable
    public mutating func removeParent(of child: Entity) {
        operations.append { world, spawned in _ = try? world.removeParent(checkedOf: Self.resolve(child, in: spawned)) }
    }

    /// Records relating `source` to `target` by `relation`. When it applies, nothing happens if
    /// either entity is not live.
    @inlinable
    public mutating func relate<R: Relation>(_ source: Entity, _ relation: R, to target: Entity) {
        operations.append { world, spawned in
            try? world.relate(Self.resolve(source, in: spawned), relation, checkedTo: Self.resolve(target, in: spawned))
        }
    }

    /// Records removing the pair of `source` and `target` by `R`. When it applies, nothing
    /// happens if `source` is not live.
    @inlinable
    public mutating func unrelate<R: Relation>(_ source: Entity, _ type: R.Type, from target: Entity) {
        operations.append { world, spawned in
            _ = try? world.unrelate(Self.resolve(source, in: spawned), R.self, checkedFrom: Self.resolve(target, in: spawned))
        }
    }

    /// Records giving `entity` the components of `bundles`, replacing any it holds of the same
    /// types.
    @inlinable
    public mutating func insert<each B: Bundle>(_ bundles: repeat each B, into entity: Entity) {
        operations.append { world, spawned in
            try? world.insert(repeat each bundles, checkedInto: Self.resolve(entity, in: spawned))
        }
    }

    /// Records triggering `event` on `entity`. When it applies, nothing happens if `entity` is
    /// not live.
    @inlinable
    public mutating func trigger<E: EntityEvent>(_ event: E, on entity: Entity) {
        operations.append { world, spawned in try? world.trigger(event, checkedOn: Self.resolve(entity, in: spawned)) }
    }

    /// Records storing `resource`, replacing any of its type.
    @inlinable
    public mutating func insert<R: Resource>(resource: R) {
        operations.append { world, _ in world.resources.insert(resource) }
    }

    /// Records a change of `world` by `body`.
    @inlinable
    public mutating func record(_ body: @escaping @Sendable (inout World) -> Void) {
        operations.append { world, _ in body(&world) }
    }
}

extension World {
    /// Applies `commands` in the order they were recorded, and returns the entities its spawn
    /// commands created, in the order they were recorded.
    ///
    /// - Complexity: The sum of the commands' costs.
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
    /// Queues `commands` to apply later, with ``applyQueuedCommands()``.
    ///
    /// A system that records commands while it runs alongside others queues them, since applying
    /// would change entities the others are reading; a `Schedule` applies every queued
    /// buffer at the end of each wave of systems it runs together.
    ///
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func queue(_ commands: Commands) {
        queuedCommands.append(commands)
    }

    /// Whether any command buffers are queued.
    @inlinable
    public var hasQueuedCommands: Bool { !queuedCommands.isEmpty }

    /// Applies every queued command buffer, in the order they were queued, and empties the queue.
    ///
    /// - Returns: The entities the buffers' spawn commands created, in the order they were
    ///   recorded.
    /// - Complexity: The sum of the commands' costs.
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
