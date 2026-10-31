import WorldModule

/// A type whose values are the states a simulation can be in.
///
/// A state type is usually an enumeration, such as the screens of a game:
///
/// ```swift
/// enum Screen: States { case title, level, credits }
///
/// var simulation = Simulation()
/// simulation.add(state: Screen.title)
/// simulation.update(elapsed: .zero)
/// print(simulation.world.resources[CurrentState<Screen>.self].state)
/// // Prints "title"
/// ```
///
/// Add a state type to a simulation with ``Simulation/add(state:)``, change the state through
/// ``NextState``, and run systems only in one state with ``inState(_:)``.
public protocol States: Hashable, Sendable {}

/// A resource holding the state a simulation is in.
///
/// The simulation sets this resource on its first frame, and changes it at the start of a frame
/// after a system sets ``NextState``. Read it to find the current state; to change the state, set
/// ``NextState`` instead.
@frozen
public struct CurrentState<S: States>: Resource {
    /// The current state.
    public let state: S

    @inlinable
    init(_ state: S) {
        self.state = state
    }
}

/// A resource holding the state a simulation enters at the start of its next frame.
///
/// To change the state, set the pending state, from a system or between frames:
///
/// ```swift
/// var simulation = Simulation()
/// simulation.add(state: GameState.playing)
/// simulation.update(elapsed: .zero)
///
/// simulation.world.resources[NextState<GameState>.self].set(.paused)
/// simulation.update(elapsed: .zero)
/// print(simulation.world.resources[CurrentState<GameState>.self].state)
/// // Prints "paused"
/// ```
///
/// When the next frame applies the change, it clears the pending state.
@frozen
public struct NextState<S: States>: Resource {
    /// The state to enter at the start of the next frame, or `nil` if no change is pending.
    public var pending: S?

    /// Creates the resource with the given pending state.
    ///
    /// - Parameter pending: The state to enter, or `nil` for no change.
    @inlinable
    public init(_ pending: S? = nil) {
        self.pending = pending
    }

    /// Asks for the simulation to enter the given state at the start of its next frame.
    ///
    /// Setting a state replaces any change already pending.
    ///
    /// - Parameter state: The state to enter.
    @inlinable
    public mutating func set(_ state: S) {
        pending = state
    }
}

/// Returns a run condition that holds when a world's current state is the given state.
///
/// Pass the condition to `runIf(_:)` to run a system, or a whole schedule, only in one state:
///
/// ```swift
/// var world = World()
/// world.resources.insert(FixedSteps())
///
/// var simulation = Simulation(world)
/// simulation.add(state: GameState.paused)
/// simulation.add(to: .update) { CountSteps().runIf(inState(GameState.playing)) }
/// simulation.update(elapsed: .zero)
/// print(simulation.world.resources[FixedSteps.self].count)
/// // Prints "0"
/// ```
///
/// The condition doesn't hold in a world without a ``CurrentState`` of type `S`.
///
/// - Parameter state: The state the condition requires.
/// - Returns: A condition that holds when the world's ``CurrentState`` of type `S` is `state`.
@inlinable
public func inState<S: States>(_ state: S) -> @Sendable (World) -> Bool {
    { world in
        guard let current = try? world.resources[checked: CurrentState<S>.self] else { return false }
        return current.state == state
    }
}
