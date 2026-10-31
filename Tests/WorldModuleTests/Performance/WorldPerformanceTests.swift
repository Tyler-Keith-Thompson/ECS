// Speed-reliant tests: each bounds its own wall-clock time, so a regression in complexity (an
// accidental quadratic walk, a copy of a column per operation) fails it. The bounds hold for
// unoptimized builds with a wide margin; `just test-release` runs them optimized. Each test is
// self-contained.

import ECSTestSupport
import Testing
import WorldModule

@Suite("World: performance")
struct WorldPerformanceTests {
    @Test("Spawning, updating, querying and despawning 200,000 entities each take well under a second", .timeLimit(.minutes(1)))
    func lifecycle() {
        let count = 200_000
        let clock = ContinuousClock()
        var world = World()
        let spawning = clock.measure {
            for value in 0 ..< count {
                let entity = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: Double(value)))
                if value.isMultiple(of: 3) { world.insert(Frozen(), into: entity) }
            }
        }
        let updating = clock.measure {
            world.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, row in
                position.x += row.components.dx
            }
        }
        var total = 0.0
        let querying = clock.measure {
            for row in world.query(Position.self, Velocity.self) {
                total += row.components.0.x
            }
        }
        let entities = Array(world.entities)
        let despawning = clock.measure {
            for entity in entities where entity.index.isMultiple(of: 2) {
                world.despawn(entity)
            }
        }
        let limit = Duration.seconds(2)
        #expect(spawning < limit)
        #expect(updating < limit)
        #expect(querying < limit)
        #expect(despawning < limit)
        #expect(total == Double(count - (count + 2) / 3))
        #expect(world.count == count / 2)
    }

    @Test("Removing and inserting one component 200,000 times takes time linear in the count", .timeLimit(.minutes(1)))
    func churnIsLinear() {
        let clock = ContinuousClock()
        func churn(_ count: Int) -> Duration {
            var world = World()
            let entities = (0 ..< count).map { world.spawn(Health($0)) }
            return clock.measure {
                for entity in entities {
                    let health = world.remove(Health.self, from: entity)!
                    world.insert(health, into: entity)
                }
            }
        }
        _ = churn(1_000)
        let small = churn(20_000)
        let large = churn(200_000)
        // Ten times the work; a column copied per operation would make this a hundredfold.
        #expect(large < small * 40)
    }

    @Test("Writing to a copy of a large world copies only the component type written", .timeLimit(.minutes(1)))
    func copyOnWriteIsPerColumn() {
        let clock = ContinuousClock()
        var world = World()
        for value in 0 ..< 200_000 {
            world.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: 0), Health(value))
        }
        let target = world.entities.first { _ in true }!
        var copy = world
        let firstWrite = clock.measure { copy[Health.self, of: target].current = -1 }
        let laterWrites = clock.measure {
            for _ in 0 ..< 1_000 { copy[Health.self, of: target].current -= 1 }
        }
        #expect(world[Health.self, of: target].current == 0)
        #expect(copy[Health.self, of: target].current == -1_001)
        // Were each write to copy the column again, a thousand writes would cost about a thousand
        // times the first; sharing ends with the first write, so they cost far less.
        #expect(laterWrites < firstWrite * 50)
    }
}
