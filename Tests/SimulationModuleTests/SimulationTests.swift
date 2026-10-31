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
}
