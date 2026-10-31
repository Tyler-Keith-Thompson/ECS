import WorldModule

/// A resource holding the time a simulation has advanced.
///
/// A ``Simulation`` keeps this resource in its world. Read it from a system with
/// `ResourceReader<Time>` to scale a change by the frame's length:
///
/// ```swift
/// var simulation = Simulation()
/// simulation.update(elapsed: .milliseconds(16))
/// simulation.update(elapsed: .milliseconds(20))
///
/// let time = simulation.world.resources[Time.self]
/// print(time.delta)
/// // Prints "0.02 seconds"
/// print(time.elapsed)
/// // Prints "0.036 seconds"
/// ```
///
/// Systems in the ``ScheduleLabel/fixedUpdate`` schedule read ``FixedTime/timestep`` instead.
@frozen
public struct Time: Resource, Hashable {
    /// The time the current frame advanced the simulation, at most its
    /// ``Simulation/maximumDelta``.
    public internal(set) var delta: Duration
    /// The total time every frame so far advanced the simulation.
    public internal(set) var elapsed: Duration

    init() {
        delta = .zero
        elapsed = .zero
    }
}

/// A resource holding the fixed timestep of a simulation.
///
/// A ``Simulation`` keeps this resource in its world. Each run of the
/// ``ScheduleLabel/fixedUpdate`` schedule stands for one ``timestep``; the ``overstep`` is the
/// time that has passed but that no run has stood for yet.
@frozen
public struct FixedTime: Resource, Hashable {
    /// The time each run of the ``ScheduleLabel/fixedUpdate`` schedule stands for.
    public let timestep: Duration
    /// The time that has passed but that no run of the ``ScheduleLabel/fixedUpdate`` schedule
    /// has stood for yet.
    ///
    /// Between frames, the overstep is less than ``timestep``. A system can use the ratio of
    /// the two to blend between the last two fixed steps when drawing.
    public internal(set) var overstep: Duration

    init(timestep: Duration) {
        self.timestep = timestep
        overstep = .zero
    }
}
