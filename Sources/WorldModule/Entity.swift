/// A handle to an entity: the slot it occupies in a ``World`` and the generation of that slot.
///
/// A world reuses a slot once its entity is despawned, with the next generation, so a handle kept
/// past its entity's despawn is stale rather than naming whatever took the slot. Entities order by
/// slot, then by generation.
@frozen
public struct Entity: Hashable, Comparable, Sendable, Codable {
    /// The slot the entity occupies.
    public let index: UInt32
    /// How many entities held the slot before this one, wrapping at `UInt32.max`.
    public let generation: UInt32

    /// The handle for slot `index` at generation `generation`.
    ///
    /// A world hands out handles from ``World/spawn(_:)``; build one by hand only to restore a
    /// handle that was saved, and only into the world it came from.
    @inlinable
    public init(index: UInt32, generation: UInt32) {
        self.index = index
        self.generation = generation
    }

    @inlinable
    public static func < (lhs: Entity, rhs: Entity) -> Bool {
        (lhs.index, lhs.generation) < (rhs.index, rhs.generation)
    }
}

extension Entity: CustomStringConvertible {
    /// The slot and generation, as `index:generation`.
    public var description: String { "\(index):\(generation)" }
}
