import Systems
import WorldModule

/// An error that indicates a simulation's fixed timestep or maximum frame time is zero or
/// negative.
///
/// ``Simulation/init(_:checkedFixedTimestep:maximumDelta:)`` throws this error.
@frozen
public struct NonPositiveDuration: Error, Hashable, Sendable {
    /// Creates the error.
    @inlinable
    public init() {}
}

/// A world and its schedules by label, advanced one frame at a time.
///
/// Use a simulation to drive a world from a game loop, a timer or a test. You add systems to
/// schedules named by ``ScheduleLabel``, then call ``update(elapsed:)`` once a frame with the time
/// that passed since the last one.
///
/// The following example counts the runs of the fixed-timestep schedule. With a timestep of 10
/// milliseconds, a frame of 25 milliseconds runs it twice and carries the remaining 5
/// milliseconds over to the next frame:
///
/// ```swift
/// var world = World()
/// world.resources.insert(FixedSteps())
///
/// var simulation = Simulation(world, fixedTimestep: .milliseconds(10))
/// simulation.add(to: .fixedUpdate) { CountSteps() }
///
/// simulation.update(elapsed: .milliseconds(25))
/// print(simulation.world.resources[FixedSteps.self].count)
/// // Prints "2"
/// print(simulation.world.resources[FixedTime.self].overstep)
/// // Prints "0.005 seconds"
///
/// simulation.update(elapsed: .milliseconds(25))
/// print(simulation.world.resources[FixedSteps.self].count)
/// // Prints "5"
/// ```
///
/// ### The Order of a Frame
///
/// Each call to ``update(elapsed:)`` is one frame, which runs in this order:
///
/// 1. On the first frame only, the ``ScheduleLabel/startup`` schedule.
/// 2. The world's events update, dropping events older than the previous frame.
/// 3. The ``Time`` resource advances by the frame's time, at most ``maximumDelta``.
/// 4. Each state type's pending change applies, in the order the types were added, running its
///    ``ScheduleLabel/onExit(_:)``, ``ScheduleLabel/onTransition(from:to:)`` and
///    ``ScheduleLabel/onEnter(_:)`` schedules.
/// 5. The ``ScheduleLabel/fixedUpdate`` schedule, once for each whole fixed timestep of time not
///    yet stood for, which ``FixedTime`` tracks.
/// 6. The ``ScheduleLabel/update`` schedule.
///
/// A label with no systems added is skipped. Systems read the frame's time through the
/// ``Time`` and ``FixedTime`` resources, which the simulation's world always holds.
public struct Simulation: Sendable {
    /// The world the schedules run on.
    ///
    /// Read the world to inspect the simulation's results, or change it between frames, such as
    /// to set a ``NextState`` or insert a resource.
    public var world: World
    /// The simulation's schedules, keyed by label.
    public private(set) var schedules: [ScheduleLabel: Schedule] = [:]
    /// The most time a single frame advances.
    ///
    /// A call to ``update(elapsed:)`` with a longer time advances the simulation by this much
    /// instead, so a stall, such as a debugger pause, doesn't run the fixed-timestep schedule many
    /// times over to catch up.
    public let maximumDelta: Duration
    /// Applies the pending change of each state type, in the order the types were added.
    var transitions: [@Sendable (inout Simulation) -> Void] = []
    var hasStarted = false

    /// Creates a simulation of a world with the given fixed timestep.
    ///
    /// The simulation inserts the ``Time`` and ``FixedTime`` resources into the world, replacing
    /// any it already holds.
    ///
    /// - Parameters:
    ///   - world: The world to run. The default is an empty world.
    ///   - fixedTimestep: The time each run of the ``ScheduleLabel/fixedUpdate`` schedule stands
    ///     for. The default is 1/64 second.
    ///   - maximumDelta: The most time a single frame advances. The default is 250 milliseconds.
    /// - Precondition: `fixedTimestep` and `maximumDelta` are positive. The checked spelling,
    ///   ``init(_:checkedFixedTimestep:maximumDelta:)``, throws instead.
    public init(_ world: World = World(), fixedTimestep: Duration = .seconds(1) / 64, maximumDelta: Duration = .milliseconds(250)) {
        precondition(fixedTimestep > .zero && maximumDelta > .zero, "A simulation's fixed timestep and maximum frame time are positive")
        self.world = world
        self.maximumDelta = maximumDelta
        self.world.resources.insert(Time())
        self.world.resources.insert(FixedTime(timestep: fixedTimestep))
    }

    /// Creates a simulation of a world with the given fixed timestep, throwing an error if a
    /// duration isn't positive.
    ///
    /// Use this initializer when the timestep comes from outside your code, such as a settings
    /// file:
    ///
    /// ```swift
    /// let timestep: Duration = .zero
    /// do {
    ///     _ = try Simulation(checkedFixedTimestep: timestep)
    /// } catch {
    ///     print(error)
    ///     // Prints "NonPositiveDuration()"
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - world: The world to run. The default is an empty world.
    ///   - fixedTimestep: The time each run of the ``ScheduleLabel/fixedUpdate`` schedule stands
    ///     for.
    ///   - maximumDelta: The most time a single frame advances. The default is 250 milliseconds.
    /// - Throws: ``NonPositiveDuration`` if `fixedTimestep` or `maximumDelta` is zero or
    ///   negative.
    public init(_ world: World = World(), checkedFixedTimestep fixedTimestep: Duration, maximumDelta: Duration = .milliseconds(250)) throws(NonPositiveDuration) {
        guard fixedTimestep > .zero, maximumDelta > .zero else { throw NonPositiveDuration() }
        self.init(world, fixedTimestep: fixedTimestep, maximumDelta: maximumDelta)
    }

    /// Adds systems to the schedule with the given label.
    ///
    /// The systems join the end of the label's schedule, creating it if the label has none, and
    /// take part in its ordering with the systems already there:
    ///
    /// ```swift
    /// var simulation = Simulation()
    /// simulation.add(to: .startup) { SpawnBall() }
    /// simulation.add(to: .fixedUpdate) { Physics() }
    /// simulation.add(to: .fixedUpdate) { CountSteps() }
    /// print(simulation.schedules[.fixedUpdate]?.names ?? [])
    /// // Prints "["Physics", "CountSteps"]"
    /// ```
    ///
    /// - Parameters:
    ///   - label: The label of the schedule to add to.
    ///   - build: A closure listing the systems to add, written as in a ``/Systems/Schedule``.
    /// - Precondition: The schedule's ordering constraints form no cycle.
    public mutating func add(to label: ScheduleLabel, @ScheduleBuilder _ build: () -> [ScheduledSystem]) {
        let existing = schedules[label]
        let added = build()
        schedules[label] = Schedule {
            if let existing { existing }
            for system in added { system }
        }
    }

    /// Adds a state type to the simulation, starting in the given state.
    ///
    /// The first frame enters `initial`, running its ``ScheduleLabel/onEnter(_:)`` schedule, and
    /// sets the ``CurrentState`` resource. To change the state, a system sets the ``NextState``
    /// resource. The change applies at the start of the next frame, running in order the
    /// ``ScheduleLabel/onExit(_:)`` schedule of the state left, the
    /// ``ScheduleLabel/onTransition(from:to:)`` schedule, and the ``ScheduleLabel/onEnter(_:)``
    /// schedule of the state entered. Setting the state the simulation is already in changes
    /// nothing.
    ///
    /// The following example pauses a game and records the schedules the change runs:
    ///
    /// ```swift
    /// var world = World()
    /// world.resources.insert(FixedSteps())
    ///
    /// var simulation = Simulation(world)
    /// simulation.add(state: GameState.playing)
    /// simulation.add(to: .onExit(GameState.playing)) { CountSteps() }
    /// simulation.add(to: .onEnter(GameState.paused)) { CountSteps() }
    /// simulation.update(elapsed: .zero)
    ///
    /// simulation.world.resources[NextState<GameState>.self].set(.paused)
    /// simulation.update(elapsed: .zero)
    /// print(simulation.world.resources[CurrentState<GameState>.self].state)
    /// // Prints "paused"
    /// print(simulation.world.resources[FixedSteps.self].count)
    /// // Prints "2"
    /// ```
    ///
    /// - Parameter initial: The state the simulation starts in.
    /// - Precondition: The simulation doesn't already have the state type `S`.
    public mutating func add<S: States>(state initial: S) {
        precondition(!world.resources.contains(NextState<S>.self), "The state type \(S.self) is already added")
        world.resources.insert(NextState(initial))
        transitions.append { simulation in
            guard let next = simulation.world.resources[NextState<S>.self].pending else { return }
            simulation.world.resources[NextState<S>.self].pending = nil
            let current = try? simulation.world.resources[checked: CurrentState<S>.self].state
            guard current != next else { return }
            if let current {
                simulation.run(.onExit(current))
                simulation.run(.onTransition(from: current, to: next))
            }
            simulation.world.resources.insert(CurrentState(next))
            simulation.run(.onEnter(next))
        }
    }

    /// Runs the schedule with the given label once, outside the order of a frame.
    ///
    /// Use this method to run a schedule of your own label on demand, such as one that saves
    /// the game. If no systems have been added to `label`, this method does nothing.
    ///
    /// - Parameter label: The label of the schedule to run.
    public mutating func run(_ label: ScheduleLabel) {
        schedules[label]?.run(on: &world)
    }

    /// Advances the simulation by one frame.
    ///
    /// Call this method once a frame, passing the time since the previous frame. The frame
    /// advances by `elapsed`, or by ``maximumDelta`` if `elapsed` is longer. See the order a
    /// frame runs its schedules in at ``Simulation``.
    ///
    /// - Parameter elapsed: The time since the previous frame.
    /// - Precondition: `elapsed` isn't negative.
    public mutating func update(elapsed: Duration) {
        precondition(elapsed >= .zero, "A frame cannot advance a negative time")
        if !hasStarted {
            hasStarted = true
            run(.startup)
        }
        world.updateEvents()
        let delta = min(elapsed, maximumDelta)
        world.resources[Time.self].delta = delta
        world.resources[Time.self].elapsed += delta
        for transition in transitions {
            transition(&self)
        }
        world.resources[FixedTime.self].overstep += delta
        let timestep = world.resources[FixedTime.self].timestep
        while world.resources[FixedTime.self].overstep >= timestep {
            world.resources[FixedTime.self].overstep -= timestep
            run(.fixedUpdate)
        }
        run(.update)
    }
}
