// Systems declared by their parameters with @System, run through schedules. Self-contained:
// the systems each test runs are declared below.

import ECSTestSupport
import PropertyBased
import Systems
import Testing
import WorldModule

struct Tally: Resource, Equatable { var count = 0 }
struct Signal: Event, Equatable { var value: Int }
struct Seen: Resource, Equatable { var values: [Int] = [] }
typealias Place = Position

private struct FirstFound: Resource { var entity: Entity?, unfrozen: Entity? }

@System
private struct ParameterFindFirst {
    func run(_ healthy: Query<Health>, _ unfrozen: Query<Health>.Where<Without<Frozen>>, found: ResourceWriter<FirstFound>) {
        found.value.entity = healthy.first?.entity
        found.value.unfrozen = unfrozen.first?.entity
    }
}

@System
struct ParameterMovement {
    func run(_ movers: Update<Position>.Over<Velocity>.Where<Without<Frozen>>) {
        movers { position, row in
            position.x += row.components.dx
            position.y += row.components.dy
        }
    }
}

@System
struct ParameterAger {
    func run(_ health: Update<Health>, clock: ResourceReader<Clock>) {
        let ticks = clock.value.ticks
        health { health, _ in health.current -= ticks }
    }
}

@System
struct ParameterSwapper {
    func run(_ pairs: Update<First>.And<Second>) {
        pairs { first, second, _ in swap(&first.value, &second.value) }
    }
}

@System
struct ParameterCounter {
    func run(_ positions: Query<Position>.Where<Without<Frozen>>, tally: ResourceWriter<Tally>) {
        for _ in positions {
            tally.value.count += 1
        }
    }
}

@System
struct ParameterPinger {
    func run(clock: ResourceReader<Clock>, pings: EventWriter<Signal>) {
        pings.send(Signal(value: clock.value.ticks))
    }
}

@System
struct ParameterListener {
    func run(_ pings: EventReader<Signal>, seen: ResourceWriter<Seen>) {
        seen.value.values += pings.map { $0.value }
    }
}

@System
struct ParameterSpawner {
    func run(clock: ResourceReader<Clock>, commands: inout Commands) {
        commands.spawn(Health(clock.value.ticks))
    }
}

@System
struct ParameterHealthCounter {
    func run(_ health: Query<Health>, tally: ResourceWriter<Tally>) {
        tally.value.count = health.reduce(0) { count, _ in count + 1 }
    }
}

@System
struct ParameterWorldSystem {
    func run(_ world: inout World) {
        world.resources[Tally.self].count += 100
    }
}

/// Writes `Position` and reads it under another name, which the macro cannot see.
@System
struct ParameterHiddenConflict {
    func run(_ positions: Update<Position>, _ places: Query<Place>) {}
}

@Suite("System parameters")
struct SystemParameterTests {
    @Test("An update over terms with a filter writes the matching entities only")
    func updateOverWhere() {
        var world = World()
        let moving = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
        let frozen = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2), Frozen())
        let still = world.spawn(Position(x: 5, y: 5))
        let schedule = Schedule { ParameterMovement() }
        schedule.run(on: &world)
        schedule.run(on: &world)
        let moved: Position = Position(x: 2, y: 4)
        let origin: Position = Position(x: 0, y: 0)
        let unmoved: Position = Position(x: 5, y: 5)
        #expect(world[Position.self, of: moving] == moved)
        #expect(world[Position.self, of: frozen] == origin)
        #expect(world[Position.self, of: still] == unmoved)
    }

    @Test("A system's access is its parameters' accesses merged")
    func access() throws {
        let movement = try #require(ParameterMovement().access)
        let ager = try #require(ParameterAger().access)
        #expect(movement.conflicts(with: .reads(Position.self)))
        #expect(!movement.conflicts(with: .reads(Velocity.self)))
        #expect(movement.conflicts(with: .writes(Velocity.self)))
        #expect(movement.conflicts(with: .writes(Frozen.self)))
        #expect(!movement.conflicts(with: ager))
        #expect(ager.conflicts(with: .writes(resources: Clock.self)))
        #expect(!ager.conflicts(with: .reads(resources: Clock.self)))
    }

    @Test("A run taking the world has no access and runs as written")
    func worldSystem() {
        var world = World()
        world.resources.insert(Tally())
        #expect(ParameterWorldSystem().access == nil)
        Schedule { ParameterWorldSystem() }.run(on: &world)
        let expected: Tally = Tally(count: 100)
        #expect(world.resources[Tally.self] == expected)
    }

    @Test("An update without terms passes each written component and reads a resource")
    func updateWithResource() {
        var world = World()
        world.resources.insert(Clock(ticks: 3))
        let entity = world.spawn(Health(10))
        Schedule { ParameterAger() }.run(on: &world)
        let expected: Health = Health(7)
        #expect(world[Health.self, of: entity] == expected)
    }

    @Test("An update of two types writes both")
    func updateAnd() {
        var world = World()
        let both = world.spawn(First(1), Second(2))
        let firstOnly = world.spawn(First(5))
        Schedule { ParameterSwapper() }.run(on: &world)
        let first: First = First(2)
        let second: Second = Second(1)
        let untouched: First = First(5)
        #expect(world[First.self, of: both] == first)
        #expect(world[Second.self, of: both] == second)
        #expect(world[First.self, of: firstOnly] == untouched)
    }

    @Test("A query parameter iterates its filtered rows; a resource writer's changes are kept")
    func queryAndResourceWriter() {
        var world = World()
        world.resources.insert(Tally())
        world.spawn(Position(x: 0, y: 0))
        world.spawn(Position(x: 1, y: 0))
        world.spawn(Position(x: 2, y: 0), Frozen())
        Schedule { ParameterCounter() }.run(on: &world)
        let expected: Tally = Tally(count: 2)
        #expect(world.resources[Tally.self] == expected)
    }

    @Test("Events sent through a writer reach a reader once, in order")
    func events() {
        var world = World()
        world.resources.insert(Clock(ticks: 1))
        world.resources.insert(Seen())
        let schedule = Schedule {
            ParameterPinger()
            ParameterListener()
        }
        schedule.run(on: &world)
        world.resources[Clock.self].ticks = 2
        schedule.run(on: &world)
        let expected: Seen = Seen(values: [1, 2])
        #expect(world.resources[Seen.self] == expected)
    }

    @Test("Commands apply at the end of their wave, so a system ordered after theirs sees them")
    func commandsOrdered() {
        var world = World()
        world.resources.insert(Clock(ticks: 4))
        world.resources.insert(Tally())
        Schedule {
            ParameterSpawner()
            ParameterHealthCounter().after(ParameterSpawner.self)
        }.run(on: &world)
        let expected: Tally = Tally(count: 1)
        #expect(world.resources[Tally.self] == expected)
        #expect(!world.hasQueuedCommands)
        let health: [Health] = world.query(Health.self).map { _, health in health }
        let spawned: [Health] = [Health(4)]
        #expect(health == spawned)
    }

    @Test("A system in the same wave as a command's system does not see it, run serially or not")
    func commandsSameWave() {
        func counted(serially: Bool) -> Tally {
            var world = World()
            world.resources.insert(Clock(ticks: 4))
            world.resources.insert(Tally())
            // The spawner reads Clock and queues; the counter reads Health and writes Tally.
            let schedule = Schedule {
                ParameterSpawner()
                ParameterHealthCounter()
            }
            if serially { schedule.runSerially(on: &world) } else { schedule.run(on: &world) }
            #expect(!world.hasQueuedCommands)
            let total: Int = 1
            #expect(world.query(Health.self).count == total)
            return world.resources[Tally.self]
        }
        let expected: Tally = Tally(count: 0)
        #expect(counted(serially: true) == expected)
        #expect(counted(serially: false) == expected)
    }

    @Test("Several systems' commands in one group apply in the order the systems are written")
    func commandsOrder() {
        var world = World()
        world.resources.insert(Clock(ticks: 1))
        var firstBuffer = Commands()
        firstBuffer.spawn(Name("first"))
        let first = firstBuffer
        var secondBuffer = Commands()
        secondBuffer.spawn(Name("second"))
        let second = secondBuffer
        world.runConcurrently([
            ConcurrentChange(access: Access()) { world in world.queue(first) },
            ConcurrentChange(access: Access()) { world in world.queue(second) },
        ])
        let spawned = world.applyQueuedCommands()
        let names: [Name] = spawned.map { world[Name.self, of: $0] }
        let expected: [Name] = [Name("first"), Name("second")]
        #expect(names == expected)
    }

    @Test("Running parameter systems together ends as running them one at a time", .tags(.randomized))
    func parallelMatchesSerial() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 50, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            world.resources.insert(Clock(ticks: Int.random(in: 0 ... 3, using: &generator)))
            world.resources.insert(Tally())
            world.resources.insert(Seen())
            for _ in 0 ..< Int.random(in: 0 ... 40, using: &generator) {
                let entity = world.spawn(Position(x: 0, y: 0))
                if Bool.random(using: &generator) { world.insert(Velocity(dx: 1, dy: -1), into: entity) }
                if Bool.random(using: &generator) { world.insert(Frozen(), into: entity) }
                if Bool.random(using: &generator) { world.insert(Health(10), into: entity) }
                if Bool.random(using: &generator) { world.insert(First(1), Second(2), into: entity) }
            }
            let schedule = Schedule {
                ParameterMovement()
                ParameterAger()
                ParameterSwapper()
                ParameterPinger()
                ParameterListener()
                ParameterCounter()
                ParameterSpawner()
            }
            var serial = world
            var parallel = world
            for _ in 0 ..< 3 {
                schedule.runSerially(on: &serial)
                schedule.run(on: &parallel)
            }
            func positions(_ world: World) -> [Position] { world.query(Position.self).map { _, position in position } }
            func health(_ world: World) -> [Health] { world.query(Health.self).map { _, health in health } }
            #expect(positions(serial) == positions(parallel))
            #expect(serial.resources[Tally.self] == parallel.resources[Tally.self])
            #expect(serial.resources[Seen.self] == parallel.resources[Seen.self])
            #expect(health(serial).count == health(parallel).count)
        }
    }

    @Test("Moving through a parameter system matches a loop over a dictionary", .tags(.randomized))
    func movementMatchesModel() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            var model: [Entity: Position] = [:]
            var velocities: [Entity: Velocity] = [:]
            var frozen: Set<Entity> = []
            for _ in 0 ..< Int.random(in: 0 ... 30, using: &generator) {
                let position = Position(x: Double(Int.random(in: -9 ... 9, using: &generator)), y: 0)
                let entity = world.spawn(position)
                model[entity] = position
                if Bool.random(using: &generator) {
                    let velocity = Velocity(dx: Double(Int.random(in: -3 ... 3, using: &generator)), dy: 1)
                    world.insert(velocity, into: entity)
                    velocities[entity] = velocity
                }
                if Bool.random(using: &generator) {
                    world.insert(Frozen(), into: entity)
                    frozen.insert(entity)
                }
            }
            Schedule { ParameterMovement() }.run(on: &world)
            for (entity, velocity) in velocities where !frozen.contains(entity) {
                model[entity]!.x += velocity.dx
                model[entity]!.y += velocity.dy
            }
            for entity in model.keys.sorted() {
                #expect(world[Position.self, of: entity] == model[entity])
            }
        }
    }

    @Test("A query outside a system traps")
    func unboundQueryTraps() async {
        await #expect(processExitsWith: .failure) {
            let query = Query(Position.self)
            for _ in query {}
        }
    }

    @Test("Parameters conflicting under names the macro cannot see trap when the access is read")
    func hiddenConflictTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = ParameterHiddenConflict().access
        }
    }

    @Test("Parameters conflicting under names the macro cannot see trap when a schedule takes the system")
    func hiddenConflictTrapsWhenScheduled() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            Schedule { ParameterHiddenConflict() }.run(on: &world)
        }
    }

    @Test("A query parameter's first is the first row of the world it is bound to")
    func queryParameterFirst() {
        var world = World()
        world.resources.insert(FirstFound())
        let frozen = world.spawn(Health(1), Frozen())
        let thawed = world.spawn(Health(2))
        Schedule { ParameterFindFirst() }.run(on: &world)
        #expect(world.resources[FirstFound.self].entity == frozen)
        #expect(world.resources[FirstFound.self].unfrozen == thawed)
    }

}

@System
struct ParameterReaper {
    func run(_ health: Query<Health>, commands: inout Commands) {
        for (entity, health) in health where health.current <= 0 {
            commands.despawn(entity)
        }
    }
}

@System
struct ParameterMourner {
    func run(_ gone: RemovedComponents<Health>, seen: ResourceWriter<Seen>) {
        seen.value.values += gone.map { _ in 1 }
    }
}

@Suite("System parameters: removals")
struct RemovedComponentsTests {
    @Test("A system sees the removals since its last run, starting before its first run")
    func removals() {
        var world = World()
        world.resources.insert(Seen())
        world.spawn(Health(0))
        world.spawn(Health(0))
        world.spawn(Health(5))
        let schedule = Schedule {
            ParameterReaper()
            ParameterMourner().after(ParameterReaper.self)
        }
        schedule.run(on: &world)
        let firstRun: Seen = Seen(values: [1, 1])
        #expect(world.resources[Seen.self] == firstRun)
        schedule.run(on: &world)
        #expect(world.resources[Seen.self] == firstRun)
    }

    @Test("A system's access reads the removal record and writes its own place in it")
    func access() throws {
        let access = try #require(ParameterMourner().access)
        #expect(access.conflicts(with: .writes(resources: Events<RemovedComponent<Health>>.self)))
        #expect(!access.conflicts(with: .reads(resources: Events<RemovedComponent<Health>>.self)))
    }
}

// MARK: Update shapes

@System
struct ShapeWhere {
    func run(_ firsts: Update<First>.Where<Without<Frozen>>) {
        firsts { first, _ in first.value += 1 }
    }
}

@System
struct ShapeOver {
    func run(_ firsts: Update<First>.Over<Third>) {
        firsts { first, row in first.value += row.components.value }
    }
}

@System
struct ShapeAndWhere {
    func run(_ pairs: Update<First>.And<Second>.Where<Without<Frozen>>) {
        pairs { first, second, _ in
            first.value += 1
            second.value += 1
        }
    }
}

@System
struct ShapeAndOver {
    func run(_ pairs: Update<First>.And<Second>.Over<Third>) {
        pairs { first, second, row in
            first.value += row.components.value
            second.value += row.components.value
        }
    }
}

@System
struct ShapeAndOverWhere {
    func run(_ pairs: Update<First>.And<Second>.Over<Third>.Where<Without<Frozen>>) {
        pairs { first, second, row in
            first.value += row.components.value
            second.value += row.components.value
        }
    }
}

@System
struct ShapeTriple {
    func run(_ triples: Update<First>.And<Second>.And<Third>) {
        triples { first, second, third, _ in
            first.value += 1
            second.value += 1
            third.value += 1
        }
    }
}

@System
struct ShapeTripleWhere {
    func run(_ triples: Update<First>.And<Second>.And<Third>.Where<Without<Frozen>>) {
        triples { first, second, third, _ in
            first.value += 1
            second.value += 1
            third.value += 1
        }
    }
}

@System
struct ShapeTripleOver {
    func run(_ triples: Update<First>.And<Second>.And<Third>.Over<Health>) {
        triples { first, second, third, row in
            first.value += row.components.current
            second.value += row.components.current
            third.value += row.components.current
        }
    }
}

@System
struct ShapeTripleOverWhere {
    func run(_ triples: Update<First>.And<Second>.And<Third>.Over<Health>.Where<Without<Frozen>>) {
        triples { first, second, third, row in
            first.value += row.components.current
            second.value += row.components.current
            third.value += row.components.current
        }
    }
}

/// Visits every Health and changes nothing.
@System
struct HealthToucher {
    func run(_ health: Update<Health>) {
        health { _, _ in }
    }
}

/// Counts the Health components changed since its last run.
@System
struct ChangedHealthCounter {
    func run(_ changed: Query<Health>.Where<Changed<Health>>, tally: ResourceWriter<Tally>) {
        tally.value.count = changed.reduce(0) { count, _ in count + 1 }
    }
}

// MARK: Resources, events and commands

@System
struct ClockReader {
    func run(clock: ResourceReader<Clock>) {}
}

@System
struct ClockWriter {
    func run(clock: ResourceWriter<Clock>) {
        clock.value.ticks += 1
    }
}

/// Queues a spawn and reaches nothing else.
@System
struct CommandsOnly {
    func run(_ commands: inout Commands) {
        commands.spawn(Name("queued"))
    }
}

struct Echoes: Resource, Equatable { var values: [Int] = [] }

/// A second reader of Signal events.
@System
struct ParameterEcho {
    func run(_ pings: EventReader<Signal>, echoes: ResourceWriter<Echoes>) {
        echoes.value.values += pings.map { $0.value }
    }
}

extension SystemParameterTests {
    @Test("Each update shape visits exactly the entities holding its written types that match its terms and pass its filters")
    func updateShapes() {
        func run(_ schedule: Schedule) -> [[Int]] {
            var world = World()
            let all = world.spawn(First(1), Second(10), Third(100), Health(1000))
            let frozen = world.spawn(First(1), Second(10), Third(100), Health(1000), Frozen())
            let pair = world.spawn(First(1), Second(10))
            schedule.run(on: &world)
            func values(_ entity: Entity) -> [Int] {
                var values = [world[First.self, of: entity].value, world[Second.self, of: entity].value]
                if world.contains(Third.self, in: entity) { values.append(world[Third.self, of: entity].value) }
                return values
            }
            return [values(all), values(frozen), values(pair)]
        }
        let whereFiltered: [[Int]] = [[2, 10, 100], [1, 10, 100], [2, 10]]
        let over: [[Int]] = [[101, 10, 100], [101, 10, 100], [1, 10]]
        let andWhere: [[Int]] = [[2, 11, 100], [1, 10, 100], [2, 11]]
        let andOver: [[Int]] = [[101, 110, 100], [101, 110, 100], [1, 10]]
        let andOverWhere: [[Int]] = [[101, 110, 100], [1, 10, 100], [1, 10]]
        let triple: [[Int]] = [[2, 11, 101], [2, 11, 101], [1, 10]]
        let tripleWhere: [[Int]] = [[2, 11, 101], [1, 10, 100], [1, 10]]
        let tripleOver: [[Int]] = [[1001, 1010, 1100], [1001, 1010, 1100], [1, 10]]
        let tripleOverWhere: [[Int]] = [[1001, 1010, 1100], [1, 10, 100], [1, 10]]
        #expect(run(Schedule { ShapeWhere() }) == whereFiltered)
        #expect(run(Schedule { ShapeOver() }) == over)
        #expect(run(Schedule { ShapeAndWhere() }) == andWhere)
        #expect(run(Schedule { ShapeAndOver() }) == andOver)
        #expect(run(Schedule { ShapeAndOverWhere() }) == andOverWhere)
        #expect(run(Schedule { ShapeTriple() }) == triple)
        #expect(run(Schedule { ShapeTripleWhere() }) == tripleWhere)
        #expect(run(Schedule { ShapeTripleOver() }) == tripleOver)
        #expect(run(Schedule { ShapeTripleOverWhere() }) == tripleOverWhere)
    }

    @Test("An update marks every written component it visits changed, even when the closure leaves it as it was")
    func updateMarksChanged() {
        func secondCount(touching: Bool) -> Int {
            var world = World()
            world.resources.insert(Tally())
            world.spawn(Health(1))
            let schedule = Schedule {
                ChangedHealthCounter()
                if touching { HealthToucher().after(ChangedHealthCounter.self) }
            }
            schedule.run(on: &world)
            schedule.run(on: &world)
            return world.resources[Tally.self].count
        }
        let touched: Int = 1
        let untouched: Int = 0
        #expect(secondCount(touching: true) == touched)
        #expect(secondCount(touching: false) == untouched)
    }

    @Test("A resource reader traps when the world does not hold the resource")
    func resourceReaderMissingTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            Schedule { ClockReader() }.run(on: &world)
        }
    }

    @Test("A resource writer traps when the world does not hold the resource")
    func resourceWriterMissingTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            Schedule { ClockWriter() }.run(on: &world)
        }
    }

    @Test("Systems that only read a resource share a wave; a writer of it does not")
    func resourceReadersShareWave() {
        let readers = Schedule {
            ParameterAger()
            ParameterPinger()
            ClockReader()
        }
        let withWriter = Schedule {
            ParameterAger()
            ClockWriter()
        }
        let one: Int = 1
        let two: Int = 2
        #expect(readers.waves.count == one)
        #expect(withWriter.waves.count == two)
    }

    @Test("A commands parameter conflicts with nothing, so its system shares a wave with any other")
    func commandsShareWave() {
        let schedule = Schedule {
            ParameterMovement()
            CommandsOnly()
            ClockWriter()
        }
        let one: Int = 1
        #expect(schedule.waves.count == one)
        var world = World()
        world.resources.insert(Clock(ticks: 0))
        schedule.run(on: &world)
        let names: [Name] = world.query(Name.self).map { _, name in name }
        let expected: [Name] = [Name("queued")]
        #expect(names == expected)
    }

    @Test("Each event reader type reads every event once, however many other readers there are")
    func eventReadersEachSeeAll() {
        var world = World()
        world.resources.insert(Clock(ticks: 1))
        world.resources.insert(Seen())
        world.resources.insert(Echoes())
        let schedule = Schedule {
            ParameterPinger()
            ParameterListener().after(ParameterPinger.self)
            ParameterEcho().after(ParameterPinger.self)
        }
        schedule.run(on: &world)
        world.resources[Clock.self].ticks = 2
        schedule.run(on: &world)
        let seen: Seen = Seen(values: [1, 2])
        let echoes: Echoes = Echoes(values: [1, 2])
        #expect(world.resources[Seen.self] == seen)
        #expect(world.resources[Echoes.self] == echoes)
    }

    @Test("An event reader that does not run while its events are dropped misses them")
    func skippedReaderMissesEvents() {
        func read(pausedFirstFrame: Bool) -> Seen {
            var world = World()
            world.resources.insert(Seen())
            if pausedFirstFrame { world.resources.insert(Paused()) }
            let frame = Schedule {
                UpdateEvents()
                ParameterListener().runIf { world in !world.resources.contains(Paused.self) }
            }
            world.send(Signal(value: 1))
            frame.run(on: &world)
            _ = world.resources.remove(Paused.self)
            frame.run(on: &world)
            return world.resources[Seen.self]
        }
        let missed: Seen = Seen(values: [])
        let delivered: Seen = Seen(values: [1])
        #expect(read(pausedFirstFrame: true) == missed)
        #expect(read(pausedFirstFrame: false) == delivered)
    }
}

/// The entities a `DepartureRecorder` was told lost a Health.
struct Departures: Resource, Equatable { var entities: [Entity] = [] }

@System
struct DepartureRecorder {
    func run(_ gone: RemovedComponents<Health>, departures: ResourceWriter<Departures>) {
        departures.value.entities += Array(gone)
    }
}

extension RemovedComponentsTests {
    @Test("Removals list removed and despawned holders oldest first, and none from before the system's first run")
    func removalsOrder() {
        var world = World()
        world.resources.insert(Departures())
        let early = world.spawn(Health(1))
        let despawned = world.spawn(Health(2))
        let stripped = world.spawn(Health(3))
        world.spawn(Health(4))
        world.remove(Health.self, from: early)
        let schedule = Schedule { DepartureRecorder() }
        schedule.run(on: &world)
        let none: [Entity] = []
        #expect(world.resources[Departures.self].entities == none)
        world.remove(Health.self, from: stripped)
        world.despawn(despawned)
        schedule.run(on: &world)
        let expected: [Entity] = [stripped, despawned]
        #expect(world.resources[Departures.self].entities == expected)
    }
}
