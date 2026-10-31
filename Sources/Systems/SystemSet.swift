/// A type that names a group of systems, so ordering constraints can refer to all of them at
/// once.
///
/// Declare a set as an empty enumeration conforming to `SystemSet`. A system joins it with
/// `inSet(_:)`, and `after(_:)`, `before(_:)` and `ambiguous(with:)` accept the set wherever they
/// accept a system type. The following example orders scoring after every physics system:
///
/// ```swift
/// enum Physics: SystemSet {}
///
/// let frame = Schedule {
///     Scoring().after(Physics.self)
///     Schedule {
///         Gravity()
///         Movement().after(Gravity.self)
///     }
///     .inSet(Physics.self)
/// }
/// print(frame.names)
/// // Prints "["Gravity", "Movement", "Scoring"]"
/// ```
///
/// Every system type is itself a set, holding each system of that type, so `after(Gravity.self)`
/// orders a system after every `Gravity` in the schedule.
public protocol SystemSet {}
