import WorldModule

/// The time a ``Simulation`` has advanced, a resource of its world.
@frozen
public struct Time: Resource, Hashable {
    /// The time the current frame advanced.
    public internal(set) var delta: Duration
    /// The time every frame so far advanced, together.
    public internal(set) var elapsed: Duration

    init() {
        delta = .zero
        elapsed = .zero
    }
}

/// The fixed timestep of a ``Simulation``'s ``ScheduleLabel/fixedUpdate`` schedule, a resource of
/// its world.
@frozen
public struct FixedTime: Resource, Hashable {
    /// The time each run of the fixed schedule stands for.
    public let timestep: Duration
    /// The time elapsed that no run of the fixed schedule has stood for yet: less than
    /// ``timestep`` between frames.
    public internal(set) var overstep: Duration

    init(timestep: Duration) {
        self.timestep = timestep
        overstep = .zero
    }
}
