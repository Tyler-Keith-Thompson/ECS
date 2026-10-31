import Systems
import WorldModule

/// The error ``Simulation/init(checkedFixedTimestep:maximumDelta:)`` throws for a timestep or
/// maximum frame time that is not positive.
@frozen
public struct NonPositiveDuration: Error, Hashable, Sendable {
    @inlinable
    public init() {}
}

/// A world and its schedules by label, stepped one frame at a time.
///
/// ```swift
/// var simulation = Simulation()
/// simulation.add(to: .startup) { SpawnPlayers() }
/// simulation.add(to: .fixedUpdate) { Physics() }
/// simulation.add(to: .update) { Movement() }
/// simulation.update(elapsed: .milliseconds(16))
/// ```
///
/// Each ``update(elapsed:)`` is a frame: before the first, the ``ScheduleLabel/startup``
/// schedule runs; then the world's events update, pending state changes apply, the
/// ``ScheduleLabel/fixedUpdate`` schedule runs once per fixed timestep elapsed, and the
/// ``ScheduleLabel/update`` schedule runs. The world holds the ``Time`` and ``FixedTime``
/// resources.
public struct Simulation: Sendable {
    /// The world the schedules run on.
    public var world: World
    /// The schedules, by label.
    public private(set) var schedules: [ScheduleLabel: Schedule] = [:]
    /// The longest time one frame advances: a longer ``update(elapsed:)`` advances this much, so a
    /// stall does not run the fixed schedule many times over.
    public let maximumDelta: Duration
    /// Applies the pending change of each state type, in the order the types were added.
    var transitions: [@Sendable (inout Simulation) -> Void] = []
    var hasStarted = false

    /// A simulation of `world` whose fixed schedule stands for `fixedTimestep` per run.
    ///
    /// - Precondition: `fixedTimestep` and `maximumDelta` are positive. Use
    ///   ``init(_:checkedFixedTimestep:maximumDelta:)`` to throw instead.
    public init(_ world: World = World(), fixedTimestep: Duration = .seconds(1) / 64, maximumDelta: Duration = .milliseconds(250)) {
        precondition(fixedTimestep > .zero && maximumDelta > .zero, "A simulation's fixed timestep and maximum frame time are positive")
        self.world = world
        self.maximumDelta = maximumDelta
        self.world.resources.insert(Time())
        self.world.resources.insert(FixedTime(timestep: fixedTimestep))
    }

    /// A simulation of `world` whose fixed schedule stands for `fixedTimestep` per run.
    ///
    /// - Throws: ``NonPositiveDuration`` when `fixedTimestep` or `maximumDelta` is not positive.
    public init(_ world: World = World(), checkedFixedTimestep fixedTimestep: Duration, maximumDelta: Duration = .milliseconds(250)) throws(NonPositiveDuration) {
        guard fixedTimestep > .zero, maximumDelta > .zero else { throw NonPositiveDuration() }
        self.init(world, fixedTimestep: fixedTimestep, maximumDelta: maximumDelta)
    }

    /// Adds the systems written in `build` to the schedule labeled `label`, after its systems.
    ///
    /// - Precondition: The schedule's ordering constraints form no cycle.
    public mutating func add(to label: ScheduleLabel, @ScheduleBuilder _ build: () -> [ScheduledSystem]) {
        let existing = schedules[label]
        let added = build()
        schedules[label] = Schedule {
            if let existing { existing }
            for system in added { system }
        }
    }

    /// Adds the state type `S`, starting in `initial`: the first frame enters it, running its
    /// ``ScheduleLabel/onEnter(_:)`` schedule.
    ///
    /// A system changes the state by setting ``NextState``; the change applies at the start of
    /// the next frame, running the ``ScheduleLabel/onExit(_:)`` schedule of the state left, the
    /// ``ScheduleLabel/onTransition(from:to:)`` schedule, then the ``ScheduleLabel/onEnter(_:)``
    /// schedule of the state entered. Setting the current state changes nothing.
    ///
    /// - Precondition: `S` has not been added.
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

    /// Runs the schedule labeled `label` once, if there is one.
    public mutating func run(_ label: ScheduleLabel) {
        schedules[label]?.run(on: &world)
    }

    /// Advances the simulation one frame of `elapsed` time, at most ``maximumDelta``.
    ///
    /// - Precondition: `elapsed` is not negative.
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
