/// A point in a world's history of changes.
///
/// A world stamps every component it adds or changes with its current ``World/changeTick``.
/// Calling ``World/advanceChangeTick()`` starts a new point, so a later query can ask what was
/// added or changed after an earlier one, with filters such as
/// ``QueryFilter/added(_:since:)-swift.type.method`` and
/// ``QueryFilter/changed(_:since:)-swift.type.method``:
///
/// ```swift
/// var world = World()
/// let start = world.changeTick
/// world.advanceChangeTick()
/// world.spawn(Position(x: 0, y: 0))
///
/// print(world.query(Position.self).added(Position.self, since: start).count)
/// // Prints "1"
/// print(world.changeTick > start)
/// // Prints "true"
/// ```
///
/// Ticks are ordered: a later tick compares greater than an earlier one. ``zero`` comes before
/// every change.
@frozen
public struct ChangeTick: Hashable, Comparable, Sendable, Codable {
    /// The tick's position in the world's history, counting from ``zero``.
    public let value: UInt64

    /// Creates the tick at the given position in a world's history.
    ///
    /// A world hands out ticks through ``World/changeTick``, so you rarely need this
    /// initializer. Use it to restore a tick you saved.
    ///
    /// - Parameter value: The tick's position, counting from ``zero``.
    @inlinable
    public init(_ value: UInt64) {
        self.value = value
    }

    /// The tick before any change: every component was added and changed after it.
    public static let zero = ChangeTick(0)

    /// Returns a Boolean value indicating whether the first tick comes before the second.
    @inlinable
    public static func < (lhs: ChangeTick, rhs: ChangeTick) -> Bool {
        lhs.value < rhs.value
    }
}
