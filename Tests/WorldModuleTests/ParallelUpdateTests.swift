// Each test is self-contained: it builds its own worlds and states its own expectations.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("Parallel updates")
struct ParallelUpdateTests {
    @Test("A parallel update over many entities gives the same world as a serial one")
    func agreesWithSerial() {
        var world = World()
        for value in 0 ..< 20_000 {
            let entity = world.spawn(Position(x: Double(value), y: 0), Velocity(dx: Double(value % 7), dy: 1))
            if value.isMultiple(of: 3) { world.insert(Frozen(), into: entity) }
            if value.isMultiple(of: 5) { world.insert(Health(value), into: entity) }
        }
        var serial = world
        var parallel = world
        serial.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, row in
            position.x += row.components.dx
        }
        parallel.parallelUpdate(Position.self, reading: Velocity.self, where: .without(Frozen.self), minimumChunk: 100) { position, row in
            position.x += row.components.dx
        }
        #expect(parallel.snapshot(Position.self) == serial.snapshot(Position.self))
        #expect(parallel.snapshot(Position.self) != world.snapshot(Position.self))
    }

    @Test("Every arity agrees with the serial update")
    func arities() {
        var world = World()
        for value in 0 ..< 5_000 {
            world.spawn(Health(value), First(value), Second(value * 2))
            if value.isMultiple(of: 2) { world.insert(Third(value * 3), into: world.spawn(Health(value), First(value), Second(1))) }
        }
        var serial = world
        var parallel = world
        serial.update(Health.self) { health, _ in health.current += 1 }
        parallel.parallelUpdate(Health.self, minimumChunk: 64) { health, _ in health.current += 1 }
        serial.update(Health.self, reading: First.self) { health, row in health.current += row.components.value }
        parallel.parallelUpdate(Health.self, reading: First.self, minimumChunk: 64) { health, row in health.current += row.components.value }
        serial.update(Health.self, reading: First.self, Second.self) { health, row in health.current += row.components.1.value }
        parallel.parallelUpdate(Health.self, reading: First.self, Second.self, minimumChunk: 64) { health, row in health.current += row.components.1.value }
        serial.update(Health.self, reading: First.self, Second.self, Third.self) { health, row in health.current -= row.components.2.value }
        parallel.parallelUpdate(Health.self, reading: First.self, Second.self, Third.self, minimumChunk: 64) { health, row in health.current -= row.components.2.value }
        serial.update(Health.self, reading: First.self, Second.self, Third.self, Velocity.self) { health, _ in health.current = 0 }
        parallel.parallelUpdate(Health.self, reading: First.self, Second.self, Third.self, Velocity.self, minimumChunk: 64) { health, _ in health.current = 0 }
        #expect(parallel.snapshot(Health.self) == serial.snapshot(Health.self))
    }

    @Test("A parallel update marks every visited component changed")
    func marksChanged() {
        var world = World()
        for value in 0 ..< 1_000 { world.spawn(Health(value)) }
        world.advanceChangeTick()
        let checkpoint = world.changeTick
        world.parallelUpdate(Health.self, minimumChunk: 10) { health, _ in health.current += 1 }
        let changed = world.query(Health.self).changed(Health.self, since: ChangeTick(checkpoint.value - 1)).count
        #expect(changed == 1_000)
    }

    @Test("A parallel update of a type no entity holds, or of an empty world, changes nothing")
    func empty() {
        var world = World()
        world.parallelUpdate(Health.self) { health, _ in health.current += 1 }
        world.spawn(Name("n"))
        world.parallelUpdate(Health.self, reading: Name.self) { health, _ in health.current += 1 }
        #expect(world.count(of: Health.self) == 0)
    }

    @Test("A parallel update leaves a copy of the world unchanged")
    func copies() {
        var world = World()
        let entity = world.spawn(Health(1))
        for value in 0 ..< 1_000 { world.spawn(Health(value)) }
        let copy = world
        world.parallelUpdate(Health.self, minimumChunk: 10) { health, _ in health.current = -1 }
        #expect(copy[Health.self, of: entity] == Health(1))
        #expect(world[Health.self, of: entity] == Health(-1))
    }

    @Test("Random worlds and chunk sizes agree with the serial update", .tags(.randomized))
    func randomAgrees() async {
        let input = Gen.int(in: 0 ... 1_000_000).array(of: 0 ... 400)
        await propertyCheck(count: 100, input: input) { codes in
            var world = World()
            for code in codes {
                let entity = world.spawn(Health(code))
                if code.isMultiple(of: 2) { world.insert(First(code % 13), into: entity) }
                if code.isMultiple(of: 3) { world.insert(Frozen(), into: entity) }
            }
            let chunk = (codes.first ?? 0) % 50 + 1
            var serial = world
            var parallel = world
            serial.update(Health.self, reading: First.self, where: .without(Frozen.self)) { health, row in
                health.current = health.current &* 31 &+ row.components.value
            }
            parallel.parallelUpdate(Health.self, reading: First.self, where: .without(Frozen.self), minimumChunk: chunk) { health, row in
                health.current = health.current &* 31 &+ row.components.value
            }
            #expect(parallel.snapshot(Health.self) == serial.snapshot(Health.self))
        }
    }
}
