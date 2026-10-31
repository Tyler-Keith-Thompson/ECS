import WorldModule

/// The name of a schedule in a simulation.
///
/// A ``Simulation`` runs the schedules of its built-in labels on its own: ``startup``,
/// ``fixedUpdate`` and ``update`` as part of each frame, and the labels of a state change, such
/// as ``onEnter(_:)``, when its state changes. Declare a label of your own for a schedule you run
/// yourself with ``Simulation/run(_:)``:
///
/// ```swift
/// extension ScheduleLabel {
///     static let autosave = ScheduleLabel("Autosave")
/// }
///
/// var world = World()
/// world.resources.insert(FixedSteps())
///
/// var simulation = Simulation(world)
/// simulation.add(to: .autosave) { CountSteps() }
/// simulation.run(.autosave)
/// print(simulation.world.resources[FixedSteps.self].count)
/// // Prints "1"
/// ```
///
/// Two labels are equal when they have the same name, or, for the labels of a state change, the
/// same states.
@frozen
public struct ScheduleLabel: Hashable, Sendable, CustomStringConvertible {
    @usableFromInline let key: Key
    /// The label's name.
    public let description: String

    /// Creates a label with the given name.
    ///
    /// Two labels made with the same name are equal, so they name the same schedule.
    ///
    /// - Parameter name: The label's name.
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

    /// The label of the schedule that runs once, before the first frame.
    public static let startup = ScheduleLabel("Startup")
    /// The label of the schedule that runs once for each fixed timestep of elapsed time.
    ///
    /// The schedule runs zero or more times a frame, before ``update``. Put systems here whose
    /// result depends on how much time passes, such as physics, so each run advances by the
    /// same ``FixedTime/timestep``.
    public static let fixedUpdate = ScheduleLabel("FixedUpdate")
    /// The label of the schedule that runs once a frame.
    public static let update = ScheduleLabel("Update")

    /// Returns the label of the schedule that runs when a simulation enters the given state.
    ///
    /// The schedule also runs on the first frame, for the state the simulation starts in.
    ///
    /// - Parameter state: The state entered.
    /// - Returns: The label of the schedule that runs on entering `state`.
    @inlinable
    public static func onEnter<S: States>(_ state: S) -> ScheduleLabel {
        ScheduleLabel(key: StateLabel(kind: 0, from: nil, to: state), description: "OnEnter(\(state))")
    }

    /// Returns the label of the schedule that runs when a simulation leaves the given state.
    ///
    /// - Parameter state: The state left.
    /// - Returns: The label of the schedule that runs on leaving `state`.
    @inlinable
    public static func onExit<S: States>(_ state: S) -> ScheduleLabel {
        ScheduleLabel(key: StateLabel(kind: 1, from: state, to: nil), description: "OnExit(\(state))")
    }

    /// Returns the label of the schedule that runs when a simulation changes from one given state
    /// to another.
    ///
    /// The schedule runs after the ``onExit(_:)`` schedule of `source` and before the
    /// ``onEnter(_:)`` schedule of `destination`.
    ///
    /// - Parameters:
    ///   - source: The state left.
    ///   - destination: The state entered.
    /// - Returns: The label of the schedule that runs on changing from `source` to
    ///   `destination`.
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
