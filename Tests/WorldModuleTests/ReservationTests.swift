// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("Commands: spawned handles")
struct ReservationTests {
    @Test("Applying commands returns the entities they spawned, in the order recorded")
    func applyReturnsSpawned() {
        var world = World()
        var commands = Commands()
        commands.spawn(Health(1))
        commands.spawn(Health(2))
        let spawned = world.apply(commands)
        #expect(spawned.count == 2)
        #expect(world[Health.self, of: spawned[0]] == Health(1))
        #expect(world[Health.self, of: spawned[1]] == Health(2))
    }

    @Test("Commands with no spawns return no entities")
    func noSpawns() {
        var world = World()
        let entity = world.spawn()
        var commands = Commands()
        commands.insert(Health(1), into: entity)
        let spawned = world.apply(commands)
        let expected: [Entity] = []
        #expect(spawned == expected)
    }

    @Test("Later commands can insert into, remove from and despawn an entity spawned earlier in the buffer")
    func laterCommandsName() {
        var world = World()
        var commands = Commands()
        let kept = commands.spawn(Health(1))
        let doomed = commands.spawn(Health(2))
        commands.insert(Name("kept"), into: kept)
        commands.remove(Health.self, from: kept)
        commands.despawn(doomed)
        let spawned = world.apply(commands)
        #expect(world.count == 1)
        #expect(world[Name.self, of: spawned[0]] == Name("kept"))
        #expect(!world.contains(Health.self, in: spawned[0]))
        #expect(!world.contains(spawned[1]))
    }

    @Test("Spawned handles can be linked as parent and child in the same buffer")
    func hierarchy() {
        var world = World()
        let existing = world.spawn()
        var commands = Commands()
        let ship = commands.spawn(Name("ship"))
        let turret = commands.spawn(Name("turret"))
        commands.addChild(turret, to: ship)
        commands.addChild(ship, to: existing)
        let spawned = world.apply(commands)
        let expectedChildren = [spawned[1]]
        #expect(world.children(of: spawned[0]) == expectedChildren)
        #expect(world.parent(of: spawned[0]) == existing)
    }

    @Test("A spawned handle names no entity in the world")
    func handleIsNotLive() {
        var world = World()
        _ = world.spawn()
        var commands = Commands()
        let handle = commands.spawn(Health(1))
        world.apply(commands)
        #expect(!world.contains(handle))
    }

    @Test("A handle not yet spawned when a command applies makes that command do nothing")
    func handleBeforeItsSpawn() {
        var world = World()
        var commands = Commands()
        var other = Commands()
        let handle = other.spawn(Health(1))
        commands.insert(Name("early"), into: handle)
        let spawned = world.apply(commands)
        let expected: [Entity] = []
        #expect(spawned == expected)
        #expect(world.isEmpty)
    }

    @Test("Commands applied to two copies of a world resolve their handles in each copy")
    func copies() {
        var world = World()
        var commands = Commands()
        let parent = commands.spawn(Name("parent"))
        let child = commands.spawn(Name("child"))
        commands.addChild(child, to: parent)
        var copy = world
        _ = copy.spawn()
        let inWorld = world.apply(commands)
        let inCopy = copy.apply(commands)
        #expect(world.parent(of: inWorld[1]) == inWorld[0])
        #expect(copy.parent(of: inCopy[1]) == inCopy[0])
        #expect(inWorld != inCopy)
    }

    @Test("Any mix of spawns and commands naming spawned handles agrees with applying them directly", .tags(.randomized))
    func agreesWithDirect() async {
        let operations = Gen.int(in: 0 ... 1_000_000).array(of: 0 ... 100)
        await propertyCheck(count: 200, input: operations) { operations in
            var world = World()
            var direct = World()
            var commands = Commands()
            var handles: [Entity] = []
            var directEntities: [Entity] = []
            for code in operations {
                let argument = code / 3
                switch code % 3 {
                case 0:
                    handles.append(commands.spawn(Health(argument)))
                    directEntities.append(direct.spawn(Health(argument)))
                case 1 where !handles.isEmpty:
                    let target = argument % handles.count
                    commands.insert(Name("\(argument)"), into: handles[target])
                    try? direct.insert(Name("\(argument)"), checkedInto: directEntities[target])
                default:
                    guard !handles.isEmpty else { continue }
                    let target = argument % handles.count
                    commands.despawn(handles[target])
                    try? direct.despawn(checked: directEntities[target])
                }
            }
            let spawned = world.apply(commands)
            #expect(spawned == directEntities)
            #expect(world.count == direct.count)
            for entity in spawned where direct.contains(entity) {
                #expect(world[Health.self, of: entity] == direct[Health.self, of: entity])
                #expect((try? world[checked: Name.self, of: entity]) == (try? direct[checked: Name.self, of: entity]))
            }
        }
    }
}
