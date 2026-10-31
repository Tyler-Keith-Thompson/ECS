// Observers of entity events, and hooks for entities starting or stopping to match a query.
// Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

struct Explode: EntityEvent {
    var radius: Int
}

struct Bubble: EntityEvent {
    static var propagates: Bool { true }
    var hops = 0
}

/// What observers saw, in the order they ran.
struct Seen: Resource {
    var entries: [String] = []
}

/// The entities that match a query, as hooks report them.
struct Matching: Resource {
    var entities: Set<Entity> = []
}

@Suite("World: observers")
struct ObserverTests {
    @Test("An observer of every entity runs with the event and the entity it was triggered on")
    func globalObserver() {
        var world = World()
        world.resources.insert(Seen())
        let barrel = world.spawn(Name("barrel"))
        world.observe(Explode.self) { world, trigger in
            let name = world[Name.self, of: trigger.entity].text
            world.resources[Seen.self].entries.append("\(name) \(trigger.event.radius)")
        }
        world.trigger(Explode(radius: 3), on: barrel)
        let expected: [String] = ["barrel 3"]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("An entity's observers run for it alone, before the observers of every entity")
    func entityObserver() {
        var world = World()
        world.resources.insert(Seen())
        let barrel = world.spawn()
        let crate = world.spawn()
        world.observe(Explode.self) { world, _ in world.resources[Seen.self].entries.append("global") }
        world.observe(Explode.self, on: barrel) { world, _ in world.resources[Seen.self].entries.append("barrel") }
        world.trigger(Explode(radius: 1), on: barrel)
        world.trigger(Explode(radius: 1), on: crate)
        let expected: [String] = ["barrel", "global", "global"]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("Observers run in the order registered, and a change to the event reaches later ones")
    func orderAndChanges() {
        var world = World()
        world.resources.insert(Seen())
        let barrel = world.spawn()
        world.observe(Explode.self) { world, trigger in
            world.resources[Seen.self].entries.append("first \(trigger.event.radius)")
            trigger.event.radius *= 2
        }
        world.observe(Explode.self) { world, trigger in
            world.resources[Seen.self].entries.append("second \(trigger.event.radius)")
        }
        world.trigger(Explode(radius: 2), on: barrel)
        let expected: [String] = ["first 2", "second 4"]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("A propagating event visits each ancestor, keeping the entity it was triggered on")
    func propagation() throws {
        var world = World()
        world.resources.insert(Seen())
        let ship = world.spawn(Name("ship"))
        let deck = world.spawn(Name("deck"))
        let cannon = world.spawn(Name("cannon"))
        try world.addChild(deck, to: ship)
        try world.addChild(cannon, to: deck)
        world.observe(Bubble.self) { world, trigger in
            let here = world[Name.self, of: trigger.entity].text
            let origin = world[Name.self, of: trigger.originalEntity].text
            world.resources[Seen.self].entries.append("\(here) from \(origin) after \(trigger.event.hops)")
            trigger.event.hops += 1
        }
        world.trigger(Bubble(), on: cannon)
        let expected: [String] = ["cannon from cannon after 0", "deck from cannon after 1", "ship from cannon after 2"]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("An observer can stop a propagating event, or make one propagate")
    func stoppingAndStarting() throws {
        var world = World()
        world.resources.insert(Seen())
        let ship = world.spawn()
        let deck = world.spawn()
        let cannon = world.spawn()
        try world.addChild(deck, to: ship)
        try world.addChild(cannon, to: deck)
        world.observe(Bubble.self, on: deck) { world, trigger in
            world.resources[Seen.self].entries.append("deck stops")
            trigger.propagates = false
        }
        world.observe(Bubble.self, on: ship) { world, _ in world.resources[Seen.self].entries.append("ship") }
        world.trigger(Bubble(), on: cannon)
        world.observe(Explode.self, on: cannon) { world, trigger in
            world.resources[Seen.self].entries.append("cannon starts")
            trigger.propagates = true
        }
        world.observe(Explode.self, on: deck) { world, _ in world.resources[Seen.self].entries.append("deck") }
        world.trigger(Explode(radius: 1), on: cannon)
        let expected: [String] = ["deck stops", "cannon starts", "deck"]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("An event that does not propagate, the default, stops at the entity it was triggered on")
    func noPropagationByDefault() throws {
        var world = World()
        world.resources.insert(Seen())
        let ship = world.spawn()
        let cannon = world.spawn()
        try world.addChild(cannon, to: ship)
        world.observe(Explode.self, on: cannon) { world, trigger in
            world.resources[Seen.self].entries.append("cannon propagates \(trigger.propagates)")
        }
        world.observe(Explode.self, on: ship) { world, _ in world.resources[Seen.self].entries.append("ship") }
        world.trigger(Explode(radius: 1), on: cannon)
        let expected: [String] = ["cannon propagates false"]
        #expect(!Explode.propagates)
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("Each observer sees the world as the observers before it left it")
    func observersSeeEarlierChanges() {
        var world = World()
        world.resources.insert(Seen())
        let barrel = world.spawn(Health(3))
        world.observe(Explode.self, on: barrel) { world, trigger in
            world[Health.self, of: trigger.entity].current -= 1
        }
        world.observe(Explode.self) { world, trigger in
            world.resources[Seen.self].entries.append("global sees \(world[Health.self, of: trigger.entity].current)")
            world[Health.self, of: trigger.entity].current -= 1
        }
        world.observe(Explode.self) { world, trigger in
            world.resources[Seen.self].entries.append("last sees \(world[Health.self, of: trigger.entity].current)")
        }
        world.trigger(Explode(radius: 1), on: barrel)
        let expected: [String] = ["global sees 2", "last sees 1"]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("An observer that despawns its entity ends the event's propagation")
    func despawningObserver() throws {
        var world = World()
        world.resources.insert(Seen())
        let ship = world.spawn()
        let cannon = world.spawn()
        try world.addChild(cannon, to: ship)
        world.observe(Bubble.self, on: cannon) { world, trigger in world.despawn(trigger.entity) }
        world.observe(Bubble.self, on: ship) { world, _ in world.resources[Seen.self].entries.append("ship") }
        world.trigger(Bubble(), on: cannon)
        #expect(!world.contains(cannon))
        let none: [String] = []
        #expect(world.resources[Seen.self].entries == none)
    }

    @Test("A despawned entity's observers are forgotten; a new entity in its slot has none")
    func forgottenOnDespawn() {
        var world = World()
        world.resources.insert(Seen())
        let barrel = world.spawn()
        world.observe(Explode.self, on: barrel) { world, _ in world.resources[Seen.self].entries.append("barrel") }
        world.despawn(barrel)
        let reused = world.spawn()
        #expect(reused.index == barrel.index)
        world.trigger(Explode(radius: 1), on: reused)
        let none: [String] = []
        #expect(world.resources[Seen.self].entries == none)
    }

    @Test("Commands trigger when they apply and skip stale entities")
    func commands() {
        var world = World()
        world.resources.insert(Seen())
        let barrel = world.spawn()
        let gone = world.spawn()
        world.despawn(gone)
        world.observe(Explode.self) { world, trigger in world.resources[Seen.self].entries.append("\(trigger.event.radius)") }
        var commands = Commands()
        commands.trigger(Explode(radius: 5), on: barrel)
        commands.trigger(Explode(radius: 6), on: gone)
        world.apply(commands)
        let expected: [String] = ["5"]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("The checked trigger throws StaleEntity and runs nothing")
    func checkedTrigger() {
        var world = World()
        world.resources.insert(Seen())
        let gone = world.spawn()
        world.despawn(gone)
        world.observe(Explode.self) { world, _ in world.resources[Seen.self].entries.append("ran") }
        #expect(throws: StaleEntity()) {
            try world.trigger(Explode(radius: 1), checkedOn: gone)
        }
        let none: [String] = []
        #expect(world.resources[Seen.self].entries == none)
    }

    @Test("Triggering on a stale entity traps")
    func staleTriggerTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let gone = world.spawn()
            world.despawn(gone)
            world.trigger(Explode(radius: 1), on: gone)
        }
    }

    @Test("Observing a stale entity traps")
    func staleObserveTraps() async {
        await #expect(processExitsWith: .failure) {
            var world = World()
            let gone = world.spawn()
            world.despawn(gone)
            world.observe(Explode.self, on: gone) { _, _ in }
        }
    }
}

@Suite("World: query hooks")
struct QueryHookTests {
    @Test("A query's add hook runs when an entity starts matching, not for entities that already did")
    func addHook() {
        var world = World()
        world.resources.insert(Seen())
        let before = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        world.onAdd(Query(Position.self, Velocity.self).without(Frozen.self)) { world, entity in
            world.resources[Seen.self].entries.append("added \(entity.index)")
        }
        let spawned = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let later = world.spawn(Position(x: 0, y: 0))
        world.insert(Velocity(dx: 1, dy: 0), into: later)
        world.insert(Frozen(), into: before)
        world.remove(Frozen.self, from: before)
        let expected: [String] = ["added \(spawned.index)", "added \(later.index)", "added \(before.index)"]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("A query's remove hook runs when an entity stops matching, including by despawning or disabling")
    func removeHook() {
        var world = World()
        world.resources.insert(Seen())
        let a = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let b = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let c = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        world.onRemove(Query(Position.self, Velocity.self)) { world, entity in
            world.resources[Seen.self].entries.append("removed \(entity.index) live \(world.contains(entity))")
        }
        world.remove(Velocity.self, from: a)
        world.despawn(b)
        world.insert(Disabled(), into: c)
        let expected: [String] = ["removed \(a.index) live true", "removed \(b.index) live false", "removed \(c.index) live true"]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("Query hooks run when applied commands make an entity start or stop matching, and when enabling or disabling it")
    func commandsAndDisabling() {
        var world = World()
        world.resources.insert(Seen())
        let query = Query(Position.self, Velocity.self)
        let existing = world.spawn(Position(x: 0, y: 0))
        let disabled = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Disabled())
        world.onAdd(query) { world, entity in world.resources[Seen.self].entries.append("added \(entity.index)") }
        world.onRemove(query) { world, entity in world.resources[Seen.self].entries.append("removed \(entity.index)") }
        var commands = Commands()
        _ = commands.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        commands.insert(Velocity(dx: 1, dy: 0), into: existing)
        let applied = world.apply(commands)
        let spawnedEntity = applied[0]
        var removing = Commands()
        removing.despawn(existing)
        world.apply(removing)
        world.remove(Disabled.self, from: disabled)
        world.insert(Disabled(), into: disabled)
        let expected: [String] = [
            "added \(spawnedEntity.index)", "added \(existing.index)",
            "removed \(existing.index)",
            "added \(disabled.index)", "removed \(disabled.index)",
        ]
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("Only a query's structural conditions count for its hooks: the types it requires do, a relation filter doesn't")
    func structuralConditionsOnly() {
        var world = World()
        world.resources.insert(Seen())
        let ship = world.spawn()
        world.onAdd(Query(Position.self).with(Health.self).related(ChildOf.self, to: ship)) { world, entity in
            world.resources[Seen.self].entries.append("added \(entity.index)")
        }
        world.spawn(Position(x: 0, y: 0))
        let stranger = world.spawn(Position(x: 0, y: 0), Health(1))
        let expected: [String] = ["added \(stranger.index)"]
        #expect(world.parent(of: stranger) == nil)
        #expect(world.resources[Seen.self].entries == expected)
    }

    @Test("Query hooks run for changes a concurrent change makes, once it is merged back")
    func concurrentChanges() {
        var world = World()
        world.resources.insert(Matching())
        let a = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
        let b = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Frozen())
        let query = Query(Position.self, Velocity.self).without(Frozen.self)
        world.resources[Matching.self].entities = [a]
        world.onAdd(query) { world, entity in world.resources[Matching.self].entities.insert(entity) }
        world.onRemove(query) { world, entity in world.resources[Matching.self].entities.remove(entity) }
        world.runConcurrently([
            ConcurrentChange(access: .writes(Frozen.self)) { world in
                world.insert(Frozen(), into: a)
                world.remove(Frozen.self, from: b)
            },
        ])
        let expected: Set<Entity> = [b]
        #expect(world.resources[Matching.self].entities == expected)
    }

    @Test("Query hooks keep a set equal to the query's matches under random changes", .tags(.randomized))
    func matchesQuery() async {
        let seeds = Gen.int(in: 0 ... 1_000_000)
        await propertyCheck(count: 100, input: seeds) { seed in
            var generator = SeededRandomNumberGenerator(seed: UInt(seed))
            var world = World()
            world.resources.insert(Matching())
            let query = Query(Position.self, Velocity.self).without(Frozen.self)
            world.onAdd(query) { world, entity in world.resources[Matching.self].entities.insert(entity) }
            world.onRemove(query) { world, entity in world.resources[Matching.self].entities.remove(entity) }
            var alive: [Entity] = []
            for _ in 0 ..< Int.random(in: 0 ... 60, using: &generator) {
                let choice = Int.random(in: 0 ..< 6, using: &generator)
                if choice == 0 || alive.isEmpty {
                    alive.append(world.spawn(Position(x: 0, y: 0)))
                    continue
                }
                let entity = alive[Int.random(in: 0 ..< alive.count, using: &generator)]
                switch choice {
                case 1: world.insert(Velocity(dx: 1, dy: 0), into: entity)
                case 2: world.insert(Frozen(), into: entity)
                case 3: world.remove(Frozen.self, from: entity)
                case 4: world.remove(Velocity.self, from: entity)
                default:
                    world.despawn(entity)
                    alive.removeAll { $0 == entity }
                }
            }
            let matching: Set<Entity> = Set(world.query(query).map { $0.entity })
            #expect(world.resources[Matching.self].entities == matching)
        }
    }
}
