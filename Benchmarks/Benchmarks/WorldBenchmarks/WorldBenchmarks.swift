// Each benchmark builds its world before measurement starts and then times one operation over
// every entity. Scaled iterations are entities, so per-iteration figures are per entity.

import Benchmark
import WorldModule

struct Position: Component { var x: Double, y: Double }
struct Velocity: Component { var dx: Double, dy: Double }
struct Health: Component { var current: Int }
struct Mass: Component { var kilograms: Double }

/// Entities in each benchmark's world.
let entityCount = 1_000_000

/// A world of `entityCount` entities, each with a Position and a Velocity, every third with a
/// Health and every fifth with a Mass.
func populatedWorld() -> World {
    var world = World()
    for value in 0 ..< entityCount {
        let entity = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1))
        if value.isMultiple(of: 3) { world.insert(Health(current: 1), into: entity) }
        if value.isMultiple(of: 5) { world.insert(Mass(kilograms: 1), into: entity) }
    }
    return world
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .throughput, .mallocCountTotal, .retainCount, .releaseCount],
        scalingFactor: .mega,
        maxDuration: .seconds(3),
        maxIterations: 20
    )

    Benchmark("spawn two components, a third on every third entity") { benchmark in
        var world = World()
        for value in benchmark.scaledIterations {
            let entity = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 1))
            if value.isMultiple(of: 3) { world.insert(Health(current: 1), into: entity) }
        }
        blackHole(world.count)
    }

    Benchmark("update one type") { benchmark in
        var world = populatedWorld()
        benchmark.startMeasurement()
        world.update(Position.self) { position, _ in position.x += 1 }
        benchmark.stopMeasurement()
        blackHole(world)
    }

    Benchmark("update one type reading one") { benchmark in
        var world = populatedWorld()
        benchmark.startMeasurement()
        world.update(Position.self, reading: Velocity.self) { position, row in
            position.x += row.components.dx
            position.y += row.components.dy
        }
        benchmark.stopMeasurement()
        blackHole(world)
    }

    Benchmark("update one type reading two, a fifth matching") { benchmark in
        var world = populatedWorld()
        benchmark.startMeasurement()
        world.update(Position.self, reading: Velocity.self, Mass.self) { position, row in
            position.x += row.components.0.dx / row.components.1.kilograms
        }
        benchmark.stopMeasurement()
        blackHole(world)
    }

    Benchmark("update two types") { benchmark in
        var world = populatedWorld()
        benchmark.startMeasurement()
        world.update(Position.self, Velocity.self) { position, velocity, _ in
            position.x += velocity.dx
            velocity.dy += 1
        }
        benchmark.stopMeasurement()
        blackHole(world)
    }

    Benchmark("update one type reading four (parameter pack)") { benchmark in
        var world = populatedWorld()
        world.update(Health.self) { health, _ in health.current = 1 }
        benchmark.startMeasurement()
        world.update(Position.self, reading: Velocity.self, Health.self, Mass.self, Velocity.self) { position, row in
            position.x += Double(row.components.1.current)
        }
        benchmark.stopMeasurement()
        blackHole(world)
    }

    Benchmark("query one type") { benchmark in
        let world = populatedWorld()
        benchmark.startMeasurement()
        var total = 0.0
        for row in world.query(Position.self) { total += row.components.x }
        benchmark.stopMeasurement()
        blackHole(total)
    }

    Benchmark("query two types") { benchmark in
        let world = populatedWorld()
        benchmark.startMeasurement()
        var total = 0.0
        for row in world.query(Position.self, Velocity.self) { total += row.components.0.x + row.components.1.dx }
        benchmark.stopMeasurement()
        blackHole(total)
    }

    Benchmark("query three types, a third matching") { benchmark in
        let world = populatedWorld()
        benchmark.startMeasurement()
        var total = 0.0
        for row in world.query(Position.self, Velocity.self, Health.self) { total += row.components.0.x }
        benchmark.stopMeasurement()
        blackHole(total)
    }

    Benchmark("query one type without another") { benchmark in
        let world = populatedWorld()
        benchmark.startMeasurement()
        var total = 0.0
        for row in world.query(Position.self).without(Health.self) { total += row.components.x }
        benchmark.stopMeasurement()
        blackHole(total)
    }

    Benchmark("read one component of each entity") { benchmark in
        let world = populatedWorld()
        let entities = Array(world.entities)
        benchmark.startMeasurement()
        var total = 0.0
        for entity in entities { total += world[Position.self, of: entity].x }
        benchmark.stopMeasurement()
        blackHole(total)
    }

    Benchmark("write one component of each entity") { benchmark in
        var world = populatedWorld()
        let entities = Array(world.entities)
        benchmark.startMeasurement()
        for entity in entities { world[Position.self, of: entity].x += 1 }
        benchmark.stopMeasurement()
        blackHole(world)
    }

    Benchmark("remove or insert one component of each entity") { benchmark in
        var world = populatedWorld()
        let entities = Array(world.entities)
        benchmark.startMeasurement()
        for entity in entities where world.remove(Health.self, from: entity) == nil {
            world.insert(Health(current: 2), into: entity)
        }
        benchmark.stopMeasurement()
        blackHole(world)
    }

    Benchmark("despawn every entity") { benchmark in
        var world = populatedWorld()
        let entities = Array(world.entities)
        benchmark.startMeasurement()
        for entity in entities { world.despawn(entity) }
        benchmark.stopMeasurement()
        blackHole(world)
    }
}
