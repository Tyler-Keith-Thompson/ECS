import WorldModule

/// The name of a schedule in a ``Simulation``: one it runs each frame, such as ``update``, or one
/// a state change runs, such as ``onEnter(_:)``.
///
/// ```swift
/// extension ScheduleLabel {
///     static let rendering = ScheduleLabel("Rendering")
/// }
/// ```
@frozen
public struct ScheduleLabel: Hashable, Sendable, CustomStringConvertible {
    @usableFromInline let key: Key
    public let description: String

    /// A label named `name`; two labels with the same name are the same label.
    @inlinable
    public init(_ name: String) {
        key = Key(name)
        description = name
    }

    @inlinable
    init(key: some Hashable & Sendable, description: String) {
        self.key = Key(key)
        self.description = description
    }

    public static func == (lhs: ScheduleLabel, rhs: ScheduleLabel) -> Bool { lhs.key == rhs.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }

    /// Runs once, before the first frame.
    public static let startup = ScheduleLabel("Startup")
    /// Runs once per fixed timestep of elapsed time, zero or more times a frame, before
    /// ``update``.
    public static let fixedUpdate = ScheduleLabel("FixedUpdate")
    /// Runs once a frame.
    public static let update = ScheduleLabel("Update")

    /// Runs when the simulation enters `state`, including its initial state.
    @inlinable
    public static func onEnter<S: States>(_ state: S) -> ScheduleLabel {
        ScheduleLabel(key: StateLabel(kind: 0, from: nil, to: state), description: "OnEnter(\(state))")
    }

    /// Runs when the simulation leaves `state`.
    @inlinable
    public static func onExit<S: States>(_ state: S) -> ScheduleLabel {
        ScheduleLabel(key: StateLabel(kind: 1, from: state, to: nil), description: "OnExit(\(state))")
    }

    /// Runs when the simulation changes from `source` to `destination`, after ``onExit(_:)`` of
    /// `source` and before ``onEnter(_:)`` of `destination`.
    @inlinable
    public static func onTransition<S: States>(from source: S, to destination: S) -> ScheduleLabel {
        ScheduleLabel(key: StateLabel(kind: 2, from: source, to: destination), description: "OnTransition(\(source) → \(destination))")
    }

    /// A hashable, sendable value, compared and hashed as the value it was made from.
    @usableFromInline
    struct Key: Hashable, @unchecked Sendable {
        // Made only from `Hashable & Sendable` values, so sharing it across threads is safe.
        @usableFromInline let value: AnyHashable

        @inlinable
        init(_ value: some Hashable & Sendable) {
            self.value = AnyHashable(value)
        }
    }

    /// The key of a state schedule: what happens (enter, exit, transition) between which states.
    @usableFromInline
    struct StateLabel<S: States>: Hashable, Sendable {
        @usableFromInline let kind: Int
        @usableFromInline let from: S?
        @usableFromInline let to: S?

        @inlinable
        init(kind: Int, from: S?, to: S?) {
            self.kind = kind
            self.from = from
            self.to = to
        }
    }
}
