/// A name for a group of systems that are ordered, conditioned and checked together.
///
/// A system joins a set with `inSet`, and `after`, `before` and `ambiguous(with:)` name sets as
/// they name system types: every system type is the set of its systems.
///
/// ```swift
/// enum Physics: SystemSet {}
///
/// let frame = Schedule {
///     Input()
///     Schedule {
///         Gravity()
///         Collisions().after(Gravity.self)
///     }
///     .inSet(Physics.self)
///     .after(Input.self)
///     Render().after(Physics.self)
/// }
/// ```
public protocol SystemSet {}
