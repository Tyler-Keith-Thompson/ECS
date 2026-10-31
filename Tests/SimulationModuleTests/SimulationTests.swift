// Simulations: schedules by label, the frame order, the fixed timestep and states.
// Self-contained: the systems and states each test uses are declared below.

import ECSTestSupport
import PropertyBased
import SimulationModule
import Systems
import Testing
import WorldModule

/// What ran, in order.
struct Log: Resource, Equatable { var entries: [String] = [] }

struct Note: System {
    let entry: String
    func run(in world: inout World) {
        world.resources[Log.self].entries.append(entry)
    }
}

enum Mode: States { case menu, playing, paused }

/// Asks for a state change.
struct Switch: System {
    let mode: Mode
    func run(in world: inout World) {
        world.resources[NextState<Mode>.self].set(mode)
    }
}

/// Counts fixed steps.
struct Steps: Resource, Equatable { var count = 0 }

struct Step: System {
    func run(in world: inout World) {
        world.resources[Steps.self].count += 1
    }
}

struct Ping: Event {}

struct Pinger: System {
    func run(in world: inout World) { world.send(Ping()) }
}

/// Logs how many pings it has not read.
struct PingCounter: System {
    func run(in world: inout World) {
        let count = world.readEvents(Ping.self, by: PingCounter.self).count
        world.resources[Log.self].entries.append("pings \(count)")
    }
}

/// Logs the frame's time delta and the total elapsed time.
struct NoteTime: System {
    let entry: String
    func run(in world: inout World) {
        let time = world.resources[Time.self]
        world.resources[Log.self].entries.append("\(entry) \(time.delta) \(time.elapsed)")
    }
}

/// Logs its own name, so ordering constraints can name its type.
struct First: System {
    func run(in world: inout World) {
        world.resources[Log.self].entries.append("first")
    }
}

/// Logs its own name, so ordering constraints can name its type.
struct Second: System {
    func run(in world: inout World) {
        world.resources[Log.self].entries.append("second")
    }
}

enum Weather: States { case sunny, rainy }

@Suite("Simulation")
struct SimulationTests {
    @Test("Startup runs once, before the first frame's update")
    func startupOnce() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        simulation.add(to: .startup) { Note(entry: "startup") }
        simulation.add(to: .update) { Note(entry: "update") }
        simulation.update(elapsed: .zero)
        simulation.update(elapsed: .zero)
        let expected: [String] = ["startup", "update", "update"]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("Adding to a label appends to its schedule")
    func addAppends() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        simulation.add(to: .update) { Note(entry: "first") }
        simulation.add(to: .update) { Note(entry: "second") }
        simulation.update(elapsed: .zero)
        let expected: [String] = ["first", "second"]
        #expect(simulation.world.resources[Log.self].entries == expected)
        let names: [String] = ["Note", "Note"]
        #expect(simulation.schedules[.update]?.names == names)
    }

    @Test("A custom label runs only when asked")
    func customLabel() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        let rendering = ScheduleLabel("Rendering")
        simulation.add(to: rendering) { Note(entry: "render") }
        simulation.update(elapsed: .zero)
        #expect(simulation.world.resources[Log.self].entries.isEmpty)
        simulation.run(rendering)
        simulation.run(ScheduleLabel("Rendering"))
        let expected: [String] = ["render", "render"]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("Running a label with no schedule does nothing")
    func missingLabel() {
        var simulation = Simulation()
        let before = simulation.world.changeTick
        simulation.run(ScheduleLabel("Nothing"))
        #expect(simulation.world.changeTick == before)
    }

    @Test("Labels compare by name, and state labels by kind and states")
    func labels() {
        #expect(ScheduleLabel("Update") == .update)
        #expect(ScheduleLabel.onEnter(Mode.menu) == .onEnter(Mode.menu))
        #expect(ScheduleLabel.onEnter(Mode.menu) != .onExit(Mode.menu))
        #expect(ScheduleLabel.onEnter(Mode.menu) != .onEnter(Mode.playing))
        #expect(ScheduleLabel.onTransition(from: Mode.menu, to: .playing) != .onTransition(from: Mode.playing, to: .menu))
        let description: String = "OnEnter(menu)"
        #expect(ScheduleLabel.onEnter(Mode.menu).description == description)
    }

    @Test("Time advances by each frame's elapsed time, at most the maximum")
    func time() {
        var simulation = Simulation(maximumDelta: .milliseconds(100))
        simulation.update(elapsed: .milliseconds(30))
        simulation.update(elapsed: .seconds(5))
        let delta: Duration = .milliseconds(100)
        let elapsed: Duration = .milliseconds(130)
        #expect(simulation.world.resources[Time.self].delta == delta)
        #expect(simulation.world.resources[Time.self].elapsed == elapsed)
    }

    @Test("The fixed schedule runs once per timestep elapsed, carrying the remainder")
    func fixedTimestep() {
        var world = World()
        world.resources.insert(Steps())
        var simulation = Simulation(world, fixedTimestep: .milliseconds(10))
        simulation.add(to: .fixedUpdate) { Step() }
        simulation.update(elapsed: .milliseconds(25))
        let afterFirst: Steps = Steps(count: 2)
        let overstep: Duration = .milliseconds(5)
        #expect(simulation.world.resources[Steps.self] == afterFirst)
        #expect(simulation.world.resources[FixedTime.self].overstep == overstep)
        simulation.update(elapsed: .milliseconds(5))
        let afterSecond: Steps = Steps(count: 3)
        #expect(simulation.world.resources[Steps.self] == afterSecond)
        #expect(simulation.world.resources[FixedTime.self].overstep == .zero)
        simulation.update(elapsed: .milliseconds(9))
        #expect(simulation.world.resources[Steps.self] == afterSecond)
    }

    @Test("The fixed schedule runs before update each frame")
    func frameOrder() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world, fixedTimestep: .milliseconds(10))
        simulation.add(to: .update) { Note(entry: "update") }
        simulation.add(to: .fixedUpdate) { Note(entry: "fixed") }
        simulation.update(elapsed: .milliseconds(20))
        let expected: [String] = ["fixed", "fixed", "update"]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("Fixed runs total the elapsed time divided by the timestep", .tags(.randomized))
    func fixedRunsMatchElapsed() async {
        let frames = Gen.int(in: 0 ... 40).array(of: 0 ... 30)
        await propertyCheck(count: 200, input: frames) { frames in
            var world = World()
            world.resources.insert(Steps())
            var simulation = Simulation(world, fixedTimestep: .milliseconds(7))
            simulation.add(to: .fixedUpdate) { Step() }
            for milliseconds in frames {
                simulation.update(elapsed: .milliseconds(milliseconds))
            }
            let total = frames.reduce(0, +)
            #expect(simulation.world.resources[Steps.self].count == total / 7)
            #expect(simulation.world.resources[FixedTime.self].overstep == .milliseconds(total % 7))
        }
    }

    @Test("Events update at the start of each frame, so a reader sees them for two frames")
    func eventsUpdate() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        simulation.add(to: .startup) { Pinger() }
        simulation.update(elapsed: .zero)
        simulation.update(elapsed: .zero)
        simulation.add(to: .update) { PingCounter() }
        simulation.update(elapsed: .zero)
        let expected: [String] = ["pings 0"]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("The first frame enters the initial state")
    func initialState() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        simulation.add(state: Mode.menu)
        simulation.add(to: .onEnter(Mode.menu)) { Note(entry: "enter menu") }
        #expect(!simulation.world.resources.contains(CurrentState<Mode>.self))
        simulation.update(elapsed: .zero)
        let expected: [String] = ["enter menu"]
        #expect(simulation.world.resources[Log.self].entries == expected)
        #expect(simulation.world.resources[CurrentState<Mode>.self].state == .menu)
    }

    @Test("A change set in one frame exits, transitions and enters at the start of the next")
    func transition() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        simulation.add(state: Mode.menu)
        simulation.add(to: .onExit(Mode.menu)) { Note(entry: "exit menu") }
        simulation.add(to: .onTransition(from: Mode.menu, to: .playing)) { Note(entry: "menu → playing") }
        simulation.add(to: .onEnter(Mode.playing)) { Note(entry: "enter playing") }
        simulation.add(to: .update) {
            Note(entry: "update")
            Switch(mode: .playing).runIf(inState(Mode.menu))
        }
        simulation.update(elapsed: .zero)
        simulation.update(elapsed: .zero)
        let expected: [String] = ["update", "exit menu", "menu → playing", "enter playing", "update"]
        #expect(simulation.world.resources[Log.self].entries == expected)
        #expect(simulation.world.resources[CurrentState<Mode>.self].state == .playing)
        #expect(simulation.world.resources[NextState<Mode>.self].pending == nil)
    }

    @Test("Setting the current state changes nothing")
    func sameState() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        simulation.add(state: Mode.menu)
        simulation.add(to: .onEnter(Mode.menu)) { Note(entry: "enter menu") }
        simulation.add(to: .onExit(Mode.menu)) { Note(entry: "exit menu") }
        simulation.add(to: .update) { Switch(mode: .menu) }
        simulation.update(elapsed: .zero)
        simulation.update(elapsed: .zero)
        let expected: [String] = ["enter menu"]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("inState holds only in that state, and not before the first frame")
    func inStateCondition() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        #expect(!inState(Mode.menu)(simulation.world))
        simulation.add(state: Mode.menu)
        simulation.add(to: .update) {
            Note(entry: "playing").runIf(inState(Mode.playing))
            Note(entry: "menu").runIf(inState(Mode.menu))
        }
        #expect(!inState(Mode.menu)(simulation.world))
        simulation.update(elapsed: .zero)
        #expect(inState(Mode.menu)(simulation.world))
        #expect(!inState(Mode.playing)(simulation.world))
        let expected: [String] = ["menu"]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("A checked simulation throws for a timestep or maximum that is not positive")
    func checkedInit() throws {
        #expect(throws: NonPositiveDuration.self) { try Simulation(checkedFixedTimestep: .zero) }
        #expect(throws: NonPositiveDuration.self) { try Simulation(checkedFixedTimestep: .seconds(1), maximumDelta: .seconds(-1)) }
        let simulation = try Simulation(checkedFixedTimestep: .milliseconds(5))
        let timestep: Duration = .milliseconds(5)
        #expect(simulation.world.resources[FixedTime.self].timestep == timestep)
    }

    @Test("A timestep that is not positive traps")
    func zeroTimestepTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Simulation(fixedTimestep: .zero)
        }
    }

    @Test("A negative frame traps")
    func negativeFrameTraps() async {
        await #expect(processExitsWith: .failure) {
            var simulation = Simulation()
            simulation.update(elapsed: .seconds(-1))
        }
    }

    @Test("Adding a state type twice traps")
    func stateTwiceTraps() async {
        await #expect(processExitsWith: .failure) {
            var simulation = Simulation()
            simulation.add(state: Mode.menu)
            simulation.add(state: Mode.playing)
        }
    }

    @Test("A label made from a name describes itself by that name")
    func labelDescription() {
        let name: String = "Autosave"
        #expect(ScheduleLabel(name).description == name)
    }

    @Test("The default fixed timestep is 1/64 second and the default maximum frame time 250 milliseconds")
    func defaults() {
        var world = World()
        world.resources.insert(Steps())
        var simulation = Simulation(world)
        simulation.add(to: .fixedUpdate) { Step() }
        let timestep: Duration = .seconds(1) / 64
        let maximumDelta: Duration = .milliseconds(250)
        #expect(simulation.world.resources[FixedTime.self].timestep == timestep)
        #expect(simulation.maximumDelta == maximumDelta)
        simulation.update(elapsed: .seconds(10))
        let delta: Duration = .milliseconds(250)
        #expect(simulation.world.resources[Time.self].delta == delta)
        let steps: Steps = Steps(count: 16)
        #expect(simulation.world.resources[Steps.self] == steps)
    }

    @Test("Creating a simulation replaces the world's Time and FixedTime")
    func replacesTimeResources() {
        var stale = Simulation(fixedTimestep: .milliseconds(3))
        stale.update(elapsed: .milliseconds(40))
        let simulation = Simulation(stale.world, fixedTimestep: .milliseconds(10))
        let timestep: Duration = .milliseconds(10)
        #expect(simulation.world.resources[Time.self].elapsed == .zero)
        #expect(simulation.world.resources[Time.self].delta == .zero)
        #expect(simulation.world.resources[FixedTime.self].timestep == timestep)
        #expect(simulation.world.resources[FixedTime.self].overstep == .zero)
    }

    @Test("A long frame runs the fixed schedule only for the maximum frame time")
    func maximumDeltaLimitsFixedRuns() {
        var world = World()
        world.resources.insert(Steps())
        var simulation = Simulation(world, fixedTimestep: .milliseconds(10), maximumDelta: .milliseconds(100))
        simulation.add(to: .fixedUpdate) { Step() }
        simulation.update(elapsed: .seconds(5))
        let steps: Steps = Steps(count: 10)
        #expect(simulation.world.resources[Steps.self] == steps)
        #expect(simulation.world.resources[FixedTime.self].overstep == .zero)
    }

    @Test("A frame runs startup, then advances time, then changes state, then the fixed schedule, then update")
    func fullFrameOrder() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world, fixedTimestep: .milliseconds(10))
        simulation.add(state: Mode.menu)
        simulation.add(to: .startup) { NoteTime(entry: "startup") }
        simulation.add(to: .onEnter(Mode.menu)) { NoteTime(entry: "enter menu") }
        simulation.add(to: .fixedUpdate) { NoteTime(entry: "fixed") }
        simulation.add(to: .update) { NoteTime(entry: "update") }
        simulation.update(elapsed: .milliseconds(10))
        let expected: [String] = [
            "startup 0.0 seconds 0.0 seconds",
            "enter menu 0.01 seconds 0.01 seconds",
            "fixed 0.01 seconds 0.01 seconds",
            "update 0.01 seconds 0.01 seconds",
        ]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("A state change applies before the same frame's fixed schedule")
    func stateChangeBeforeFixed() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world, fixedTimestep: .milliseconds(10))
        simulation.add(state: Mode.menu)
        simulation.add(to: .onEnter(Mode.playing)) { Note(entry: "enter playing") }
        simulation.add(to: .fixedUpdate) {
            Note(entry: "fixed in playing").runIf(inState(Mode.playing))
        }
        simulation.update(elapsed: .zero)
        simulation.world.resources[NextState<Mode>.self].set(.playing)
        simulation.update(elapsed: .milliseconds(10))
        let expected: [String] = ["enter playing", "fixed in playing"]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("State types change in the order they were added")
    func stateTypesInOrder() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        simulation.add(state: Weather.sunny)
        simulation.add(state: Mode.menu)
        simulation.add(to: .onEnter(Mode.menu)) { Note(entry: "enter menu") }
        simulation.add(to: .onEnter(Weather.sunny)) { Note(entry: "enter sunny") }
        simulation.add(to: .onEnter(Mode.playing)) { Note(entry: "enter playing") }
        simulation.add(to: .onEnter(Weather.rainy)) { Note(entry: "enter rainy") }
        simulation.update(elapsed: .zero)
        simulation.world.resources[NextState<Mode>.self].set(.playing)
        simulation.world.resources[NextState<Weather>.self].set(.rainy)
        simulation.update(elapsed: .zero)
        let expected: [String] = ["enter sunny", "enter menu", "enter rainy", "enter playing"]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("Setting the next state replaces a change already pending")
    func setReplacesPending() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        simulation.add(state: Mode.menu)
        simulation.add(to: .onEnter(Mode.playing)) { Note(entry: "enter playing") }
        simulation.add(to: .onEnter(Mode.paused)) { Note(entry: "enter paused") }
        simulation.update(elapsed: .zero)
        simulation.world.resources[NextState<Mode>.self].set(.playing)
        simulation.world.resources[NextState<Mode>.self].set(.paused)
        let pending: Mode? = .paused
        #expect(simulation.world.resources[NextState<Mode>.self].pending == pending)
        simulation.update(elapsed: .zero)
        let expected: [String] = ["enter paused"]
        #expect(simulation.world.resources[Log.self].entries == expected)
        #expect(simulation.world.resources[CurrentState<Mode>.self].state == .paused)
    }

    @Test("Setting the current state clears the pending change without running a schedule")
    func sameStateClearsPending() {
        var simulation = Simulation()
        simulation.add(state: Mode.menu)
        simulation.update(elapsed: .zero)
        simulation.world.resources[NextState<Mode>.self].set(.menu)
        simulation.update(elapsed: .zero)
        #expect(simulation.world.resources[NextState<Mode>.self].pending == nil)
        #expect(simulation.world.resources[CurrentState<Mode>.self].state == .menu)
    }

    @Test("Systems added later take part in the ordering of the systems already in the schedule")
    func addedSystemsJoinOrdering() {
        var world = World()
        world.resources.insert(Log())
        var simulation = Simulation(world)
        simulation.add(to: .update) { Second() }
        simulation.add(to: .update) { First().before(Second.self) }
        simulation.update(elapsed: .zero)
        let expected: [String] = ["first", "second"]
        #expect(simulation.world.resources[Log.self].entries == expected)
    }

    @Test("Adding systems whose ordering forms a cycle with the schedule's traps")
    func cycleTraps() async {
        await #expect(processExitsWith: .failure) {
            var simulation = Simulation()
            simulation.add(to: .update) { First().before(Second.self) }
            simulation.add(to: .update) { Second().before(First.self) }
        }
    }

    @Test("A maximum frame time that is not positive traps")
    func zeroMaximumDeltaTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Simulation(maximumDelta: .zero)
        }
    }
}
