import WorldModule

/// The values a simulation's state can take: usually an enumeration.
///
/// ```swift
/// enum GameState: States { case menu, playing, paused }
/// ```
public protocol States: Hashable, Sendable {}

/// The state of type `S` a simulation is in, a resource of its world.
///
/// It changes only between frames, when a system has set ``NextState``.
@frozen
public struct CurrentState<S: States>: Resource {
    /// The state.
    public let state: S

    @inlinable
    init(_ state: S) {
        self.state = state
    }
}

/// The state of type `S` a simulation enters at the start of its next frame, a resource of its
/// world.
///
/// ```swift
/// world.resources[NextState<GameState>.self].set(.paused)
/// ```
@frozen
public struct NextState<S: States>: Resource {
    /// The state to enter, if a change is pending.
    public var pending: S?

    @inlinable
    public init(_ pending: S? = nil) {
        self.pending = pending
    }

    /// Asks for the simulation to enter `state` at the start of its next frame.
    @inlinable
    public mutating func set(_ state: S) {
        pending = state
    }
}

/// A run condition holding when the world's ``CurrentState`` of type `S` is `state`.
///
/// ```swift
/// Movement().runIf(inState(GameState.playing))
/// ```
@inlinable
public func inState<S: States>(_ state: S) -> @Sendable (World) -> Bool {
    { world in
        guard let current = try? world.resources[checked: CurrentState<S>.self] else { return false }
        return current.state == state
    }
}
