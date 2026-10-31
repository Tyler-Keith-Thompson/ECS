/// A piece of an entity's state.
///
/// An entity holds at most one component of each type. Components are plain values; behavior
/// belongs to the code that queries and updates them.
///
/// Every component is a ``Bundle`` of itself.
///
/// ```swift
/// struct Position: Component { var x: Double, y: Double }
/// ```
public protocol Component: Bundle where Body == Never {}

/// A value a ``World`` holds once, outside any entity: a clock, a random number generator, the
/// input of the current frame.
///
/// ```swift
/// struct Time: Resource { var elapsed: Duration }
/// ```
public protocol Resource: Sendable {}
