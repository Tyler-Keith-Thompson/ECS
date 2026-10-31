/// A point in a world's history of changes.
///
/// A world stamps every component it adds or changes with its current ``World/changeTick``.
/// Advancing the tick starts a new point, so a later query can ask what was added or changed
/// after an earlier one. ``zero`` is before any change.
@frozen
public struct ChangeTick: Hashable, Comparable, Sendable, Codable {
    /// The number of ticks since the world was created.
    public let value: UInt64

    /// The tick numbered `value`.
    @inlinable
    public init(_ value: UInt64) {
        self.value = value
    }

    /// Before any change: every component was added and changed after it.
    public static let zero = ChangeTick(0)

    @inlinable
    public static func < (lhs: ChangeTick, rhs: ChangeTick) -> Bool {
        lhs.value < rhs.value
    }
}
