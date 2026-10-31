// Components that require others. Each test is self-contained; the component types are below.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

struct Avatar: Component {
    static var required: some Bundle {
        Position(x: 0, y: 0)
        Health(100)
    }
}

/// Requires Avatar, which requires Position and Health: requirements are transitive.
struct PlayerCharacter: Component {
    static var required: some Bundle { Avatar() }
}

/// Three components requiring each other in a cycle.
struct CycleA: Component, Equatable {
    var value = 0
    static var required: some Bundle { CycleB() }
}

struct CycleB: Component, Equatable {
    var value = 0
    static var required: some Bundle { CycleC() }
}

struct CycleC: Component, Equatable {
    var value = 0
    static var required: some Bundle { CycleA() }
}

/// A bundle holding a component with requirements.
struct Hero: Bundle {
    var body: some Bundle {
        Name("hero")
        Avatar()
    }
}

/// A component whose requirement depends on nothing but is chosen in an if.
struct Armored: Component {
    static var heavy: Bool { true }
    static var required: some Bundle {
        if heavy { Health(500) } else { Health(1) }
    }
}

@Suite("World: required components")
struct RequiredComponentsTests {
    @Test("Spawning a component inserts what it requires")
    func spawnInsertsRequired() {
        var world = World()
        let entity = world.spawn(Avatar())
        let position: Position = Position(x: 0, y: 0)
        let health: Health = Health(100)
        #expect(world[Position.self, of: entity] == position)
        #expect(world[Health.self, of: entity] == health)
    }

    @Test("A component given explicitly is kept, written before or after the one requiring it")
    func explicitWins() {
        var world = World()
        let after = world.spawn(Avatar(), Health(5))
        let before = world.spawn(Health(6), Avatar())
        let three = world.spawn(Avatar(), Name("three"), Health(7))
        let four = world.spawn(Avatar(), Name("four"), Velocity(dx: 0, dy: 0), Health(8))
        let expectedAfter: Health = Health(5)
        let expectedBefore: Health = Health(6)
        let expectedThree: Health = Health(7)
        let expectedFour: Health = Health(8)
        #expect(world[Health.self, of: after] == expectedAfter)
        #expect(world[Health.self, of: before] == expectedBefore)
        #expect(world[Health.self, of: three] == expectedThree)
        #expect(world[Health.self, of: four] == expectedFour)
    }

    @Test("Inserting a component keeps the components the entity already holds")
    func insertKeepsExisting() {
        var world = World()
        let entity = world.spawn(Health(3))
        world.insert(Avatar(), into: entity)
        let health: Health = Health(3)
        let position: Position = Position(x: 0, y: 0)
        #expect(world[Health.self, of: entity] == health)
        #expect(world[Position.self, of: entity] == position)
    }

    @Test("Requirements are transitive")
    func transitive() {
        var world = World()
        let entity = world.spawn(PlayerCharacter())
        #expect(world.contains(Avatar.self, in: entity))
        #expect(world.contains(Position.self, in: entity))
        #expect(world.contains(Health.self, in: entity))
    }

    @Test("Requirements in a cycle insert each type once")
    func cycle() {
        var world = World()
        let entity = world.spawn(CycleA(value: 1))
        let a: CycleA = CycleA(value: 1)
        let b: CycleB = CycleB()
        let c: CycleC = CycleC()
        #expect(world[CycleA.self, of: entity] == a)
        #expect(world[CycleB.self, of: entity] == b)
        #expect(world[CycleC.self, of: entity] == c)
    }

    @Test("A component inside a bundle brings its requirements")
    func insideBundle() {
        var world = World()
        let entity = world.spawn(Hero())
        #expect(world.contains(Position.self, in: entity))
        #expect(world.contains(Name.self, in: entity))
    }

    @Test("A requirement chosen in an if inserts the chosen branch")
    func conditionalRequirement() {
        var world = World()
        let entity = world.spawn(Armored())
        let health: Health = Health(500)
        #expect(world[Health.self, of: entity] == health)
    }

    @Test("Every spawn and insert spelling inserts requirements")
    func everySpelling() throws {
        var world = World()
        let one = world.spawn(Avatar())
        let two = world.spawn(Avatar(), Name("two"))
        let three = world.spawn(Avatar(), Name("three"), Velocity(dx: 0, dy: 0))
        let pack = world.spawn(Avatar(), Name("pack"), Velocity(dx: 0, dy: 0), Frozen())
        let inserted = [world.spawn(Frozen()), world.spawn(Frozen()), world.spawn(Frozen()), world.spawn(Frozen()), world.spawn(Frozen())]
        world.insert(Avatar(), into: inserted[0])
        world.insert(Avatar(), Name("two"), into: inserted[1])
        world.insert(Avatar(), Name("three"), Velocity(dx: 0, dy: 0), into: inserted[2])
        world.insert(Avatar(), Name("pack"), Velocity(dx: 0, dy: 0), Second(1), into: inserted[3])
        try world.insert(Avatar(), checkedInto: inserted[4])
        for entity in [one, two, three, pack] + inserted {
            #expect(world.contains(Position.self, in: entity))
            #expect(world.contains(Health.self, in: entity))
        }
    }

    @Test("Commands insert requirements when they apply")
    func commands() {
        var world = World()
        let target = world.spawn(Frozen())
        var commands = Commands()
        commands.spawn(Avatar())
        commands.insert(PlayerCharacter(), into: target)
        let spawned = world.apply(commands)
        #expect(world.contains(Position.self, in: spawned[0]))
        #expect(world.contains(Health.self, in: target))
        #expect(world.contains(Avatar.self, in: target))
    }

    @Test("A required component fires the hooks of an added component")
    func hooks() {
        var world = World()
        world.resources.insert(Clock(ticks: 0))
        world.onAdd(Health.self) { world, _ in world.resources[Clock.self].ticks += 1 }
        world.spawn(Avatar())
        world.spawn(Avatar(), Health(1))
        let expected: Clock = Clock(ticks: 2)
        #expect(world.resources[Clock.self] == expected)
    }

    @Test("Removing a required component leaves the component that required it")
    func removal() {
        var world = World()
        let entity = world.spawn(Avatar())
        world.remove(Health.self, from: entity)
        #expect(world.contains(Avatar.self, in: entity))
        #expect(!world.contains(Health.self, in: entity))
    }

    @Test("Spawned entities hold the closure of their explicit components' requirements", .tags(.randomized))
    func closureMatchesModel() async {
        // Bits: 1 Avatar, 2 PlayerCharacter, 4 Health(explicit), 8 CycleB(explicit).
        let masks = Gen.int(in: 0 ... 15).array(of: 1 ... 20)
        await propertyCheck(count: 200, input: masks) { masks in
            var world = World()
            for mask in masks {
                var commands = Commands()
                let entity = world.spawn(Frozen())
                if mask & 1 != 0 { commands.insert(Avatar(), into: entity) }
                if mask & 2 != 0 { commands.insert(PlayerCharacter(), into: entity) }
                if mask & 4 != 0 { commands.insert(Health(mask), into: entity) }
                if mask & 8 != 0 { commands.insert(CycleB(value: mask), into: entity) }
                world.apply(commands)
                let hasAvatar = mask & 3 != 0
                #expect(world.contains(Avatar.self, in: entity) == hasAvatar)
                #expect(world.contains(PlayerCharacter.self, in: entity) == (mask & 2 != 0))
                #expect(world.contains(Position.self, in: entity) == hasAvatar)
                if mask & 4 != 0 {
                    #expect(world[Health.self, of: entity].current == mask)
                } else {
                    #expect(world.contains(Health.self, in: entity) == hasAvatar)
                }
                let hasCycle = mask & 8 != 0
                #expect(world.contains(CycleA.self, in: entity) == hasCycle)
                #expect(world.contains(CycleC.self, in: entity) == hasCycle)
                if hasCycle {
                    #expect(world[CycleB.self, of: entity].value == mask)
                }
            }
        }
    }
}
