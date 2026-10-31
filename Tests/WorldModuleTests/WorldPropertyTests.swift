// Randomized operation sequences checked against a naive reference: a dictionary from each live
// entity to its components. Each test is self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

@Suite("World: properties")
struct WorldPropertyTests {
    /// The reference: what each live entity holds.
    struct Model: Equatable {
        var first: [Entity: Int] = [:]
        var second: [Entity: Int] = [:]
        var third: [Entity: Int] = [:]
        var live: Set<Entity> = []
    }

    @Test("Any sequence of operations leaves the world agreeing with a dictionary model", .tags(.randomized))
    func agreesWithModel() async {
        let operations = Gen.int(in: 0 ... 1_000_000).array(of: 0 ... 300)
        await propertyCheck(count: 200, input: operations) { operations in
            Self.run(operations)
        }
    }

    @Test("Long seeded sequences leave the world agreeing with a dictionary model", .tags(.randomized), arguments: [1, 2, 3, 42, 1_000] as [UInt])
    func seeded(seed: UInt) {
        var generator = SeededRandomNumberGenerator(seed: seed)
        let operations = (0 ..< 5_000).map { _ in Int.random(in: 0 ... 1_000_000, using: &generator) }
        Self.run(operations)
    }

    static func run(_ operations: [Int]) {
        var world = World()
        var model = Model()
        var handles: [Entity] = []
        for code in operations {
            let kind = code % 9
            let argument = code / 9
            let pick = handles.isEmpty ? nil : handles[argument % handles.count]
            switch kind {
            case 0, 1:
                let entity: Entity
                switch argument % 4 {
                case 0: entity = world.spawn()
                case 1: entity = world.spawn(First(argument))
                case 2:
                    entity = world.spawn(First(argument), Second(argument &+ 1))
                    model.second[entity] = argument &+ 1
                default:
                    entity = world.spawn(Third(argument), Second(argument))
                    model.second[entity] = argument
                }
                if argument % 4 == 1 || argument % 4 == 2 { model.first[entity] = argument }
                if argument % 4 == 3 { model.third[entity] = argument }
                model.live.insert(entity)
                handles.append(entity)
            case 2:
                guard let pick else { continue }
                let expectStale = !model.live.contains(pick)
                do {
                    try world.despawn(checked: pick)
                    #expect(!expectStale)
                } catch {
                    #expect(expectStale)
                }
                model.live.remove(pick)
                model.first[pick] = nil
                model.second[pick] = nil
                model.third[pick] = nil
            case 3:
                guard let pick, model.live.contains(pick) else { continue }
                world.insert(Second(argument), into: pick)
                model.second[pick] = argument
            case 4:
                guard let pick, model.live.contains(pick) else { continue }
                let removed = world.remove(First.self, from: pick)
                #expect(removed?.value == model.first[pick])
                model.first[pick] = nil
            case 5:
                world.update(First.self, reading: Second.self) { first, row in first.value = row.components.value &+ 1 }
                for (entity, second) in model.second where model.first[entity] != nil {
                    model.first[entity] = second &+ 1
                }
            case 6:
                world.update(Second.self, Third.self, where: .without(First.self)) { second, third, _ in
                    second.value &+= 1
                    third.value &-= 1
                }
                for entity in model.second.keys where model.third[entity] != nil && model.first[entity] == nil {
                    model.second[entity]! &+= 1
                    model.third[entity]! &-= 1
                }
            case 7:
                guard let pick, model.live.contains(pick) else { continue }
                world.insert(Third(argument), First(argument), into: pick)
                model.third[pick] = argument
                model.first[pick] = argument
            default:
                guard let pick, model.live.contains(pick), model.second[pick] != nil else { continue }
                world[Second.self, of: pick].value = argument
                model.second[pick] = argument
            }
        }
        check(world, against: model)
    }

    static func check(_ world: World, against model: Model) {
        #expect(world.count == model.live.count)
        #expect(Set(world.entities) == model.live)
        #expect(world.count(of: First.self) == model.first.count)
        #expect(world.count(of: Second.self) == model.second.count)
        #expect(world.count(of: Third.self) == model.third.count)
        for entity in model.live.sorted() {
            #expect((try? world[checked: First.self, of: entity])?.value == model.first[entity])
            #expect((try? world[checked: Second.self, of: entity])?.value == model.second[entity])
            #expect((try? world[checked: Third.self, of: entity])?.value == model.third[entity])
        }
        var pairs: [Entity: [Int]] = [:]
        for (entity, first, second) in world.query(First.self, Second.self) {
            pairs[entity] = [first.value, second.value]
        }
        var expectedPairs: [Entity: [Int]] = [:]
        for (entity, first) in model.first {
            if let second = model.second[entity] { expectedPairs[entity] = [first, second] }
        }
        #expect(pairs == expectedPairs)
        let withoutFirst = Set(world.query(Second.self).without(First.self).map(\.entity))
        let expectedWithoutFirst = Set(model.second.keys.filter { model.first[$0] == nil })
        #expect(withoutFirst == expectedWithoutFirst)
        let withThird = Set(Array(world.query().with(Third.self)))
        #expect(withThird == Set(model.third.keys))
    }
}
