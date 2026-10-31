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
