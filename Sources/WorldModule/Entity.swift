/// A handle that identifies one entity in a world.
///
/// An entity is one thing in your game or simulation. It has no data of its own: a ``World``
/// stores the components it holds, and the handle is how you refer to it. You get a handle by
/// spawning an entity, and you pass it back to the world to read and change its components:
///
/// ```swift
/// var world = World()
/// let hero = world.spawn(Name(value: "Ada"), Health(current: 100))
///
/// print(world[Name.self, of: hero].value)
/// // Prints "Ada"
/// ```
///
/// A handle is a small value, cheap to copy and store, for example in a component that refers to
/// another entity. It holds two numbers: the ``index`` of the slot the entity occupies in the
/// world, and the ``generation`` of that slot. When an entity is despawned, the world can reuse
/// its slot for a new entity with the next generation, so a handle kept past its entity's despawn
/// is *stale*: it never names the entity that took the slot.
///
/// ```swift
/// var world = World()
/// let first = world.spawn(Position(x: 0, y: 0))
/// world.despawn(first)
/// let second = world.spawn(Position(x: 1, y: 1))
///
/// print(first, second)
/// // Prints "0:0 0:1"
/// print(world.contains(first))
/// // Prints "false"
/// ```
///
/// Entities are ordered by slot, then by generation.
@frozen
public struct Entity: Hashable, Comparable, Sendable, Codable {
    /// The index of the slot the entity occupies in its world.
    public let index: UInt32
    /// The number of entities that held the slot before this one.
    ///
    /// The generation wraps to 0 before reaching `UInt32.max`, which marks the placeholder
    /// handles that ``Commands/spawn(_:)`` returns.
    public let generation: UInt32

    /// Creates a handle for the entity at the given slot and generation.
    ///
    /// A world hands out handles when it spawns entities, so you rarely need this initializer.
    /// Use it only to restore a handle you saved, and only with the world it came from.
    ///
    /// - Parameters:
    ///   - index: The index of the slot the entity occupies.
    ///   - generation: The number of entities that held the slot before this one.
    @inlinable
    public init(index: UInt32, generation: UInt32) {
        self.index = index
        self.generation = generation
    }

    /// The generation of handles to entities that commands will spawn.
    @usableFromInline static let pendingGeneration = UInt32.max

    /// Returns a Boolean value indicating whether the first entity orders before the second, by
    /// slot and then by generation.
    @inlinable
    public static func < (lhs: Entity, rhs: Entity) -> Bool {
        (lhs.index, lhs.generation) < (rhs.index, rhs.generation)
    }
}

extension Entity: CustomStringConvertible {
    /// A textual representation of the entity, its slot index and generation separated by a
    /// colon, such as `3:0`.
    public var description: String { "\(index):\(generation)" }
}
