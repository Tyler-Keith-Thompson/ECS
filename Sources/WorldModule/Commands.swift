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
@frozen
public struct Commands: Sendable {
    @usableFromInline var operations: [@Sendable (inout World) -> Void] = []

    /// No commands.
    @inlinable
    public init() {}

    /// The number of commands recorded.
    @inlinable
    public var count: Int { operations.count }

    /// Whether no commands are recorded.
    @inlinable
    public var isEmpty: Bool { operations.isEmpty }

    /// Records spawning an entity holding `components`.
    @inlinable
    public mutating func spawn<each C: Component>(_ components: repeat each C) {
        operations.append { world in world.spawn(repeat each components) }
    }

    /// Records despawning `entity`.
    @inlinable
    public mutating func despawn(_ entity: Entity) {
        operations.append { world in try? world.despawn(checked: entity) }
    }

    /// Records making `child` the last child of `parent`. When it applies, nothing happens if
    /// either entity is not live or `parent` is `child` or one of its descendants.
    @inlinable
    public mutating func addChild(_ child: Entity, to parent: Entity) {
        operations.append { world in try? world.addChild(child, checkedTo: parent) }
    }

    /// Records detaching `child` from its parent. When it applies, nothing happens if `child` is
    /// not live.
    @inlinable
    public mutating func removeParent(of child: Entity) {
        operations.append { world in _ = try? world.removeParent(checkedOf: child) }
    }

    /// Records giving `entity` each of `components`, replacing any it holds of the same types.
    @inlinable
    public mutating func insert<each C: Component>(_ components: repeat each C, into entity: Entity) {
        operations.append { world in try? world.insert(repeat each components, checkedInto: entity) }
    }

    /// Records taking the `C` away from `entity`.
    @inlinable
    public mutating func remove<C: Component>(_ type: C.Type, from entity: Entity) {
        operations.append { world in _ = try? world.remove(C.self, checkedFrom: entity) }
    }

    /// Records storing `resource`, replacing any of its type.
    @inlinable
    public mutating func insert<R: Resource>(resource: R) {
        operations.append { world in world.resources.insert(resource) }
    }

    /// Records a change of `world` by `body`.
    @inlinable
    public mutating func record(_ body: @escaping @Sendable (inout World) -> Void) {
        operations.append(body)
    }
}

extension World {
    /// Applies `commands` in the order they were recorded.
    ///
    /// - Complexity: The sum of the commands' costs.
    @inlinable
    public mutating func apply(_ commands: Commands) {
        for operation in commands.operations {
            operation(&self)
        }
    }
}
