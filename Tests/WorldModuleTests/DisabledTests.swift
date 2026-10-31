// Disabled entities and other disabling components: skipped by queries and updates unless asked
// for. Self-contained.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

/// A disabling component registered by the tests that need one.
struct Template: Component {}

@Suite("World: disabled entities")
struct DisabledTests {
    @Test("Queries of every arity skip disabled entities")
    func queriesSkip() {
        var world = World()
        let enabled = world.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: 0), Health(1), Name("on"))
        world.spawn(Position(x: 0, y: 0), Velocity(dx: 0, dy: 0), Health(1), Name("off"), Disabled())
        let expected: [Entity] = [enabled]
        #expect(world.query(Position.self).map(\.entity) == expected)
        #expect(world.query(Position.self, Velocity.self).map(\.entity) == expected)
        #expect(world.query(Position.self, Velocity.self, Health.self).map(\.entity) == expected)
        #expect(world.query(Position.self, Velocity.self, Health.self, Name.self).map(\.entity) == expected)
        #expect(world.query().with(Position.self).map { $0 } == expected)
        #expect(world.query(Query(Position.self, AnyOf<Velocity, Frozen>.self)).map { $0.entity } == expected)
    }

    @Test("Allowing, naming in a filter or reading Disabled includes disabled entities")
    func optIn() {
        var world = World()
        let enabled = world.spawn(Position(x: 0, y: 0))
        let disabled = world.spawn(Position(x: 0, y: 0), Disabled())
        let both: [Entity] = [enabled, disabled]
        let onlyDisabled: [Entity] = [disabled]
        #expect(world.query(Position.self).allowing(Disabled.self).map(\.entity).sorted() == both)
        #expect(world.query(Position.self).with(Disabled.self).map(\.entity) == onlyDisabled)
        #expect(world.query(Position.self, Disabled.self).map(\.entity) == onlyDisabled)
        #expect(world.query(Position.self).filtered(by: .anyOf(.with(Disabled.self), .with(Frozen.self))).map(\.entity) == onlyDisabled)
        #expect(world.query(Query(Position.self).allowing(Disabled.self)).map { $0.entity }.sorted() == both)
        let allowsQuery = Query(Position.self).filtered(by: Query<Position>.Where<Allows<Disabled>>.filter)
        #expect(world.query(allowsQuery).map { $0.entity }.sorted() == both)
    }

    @Test("Reading a disabled entity by its handle still works")
    func directReads() {
        var world = World()
        let disabled = world.spawn(Position(x: 3, y: 0), Disabled())
        let position: Position = Position(x: 3, y: 0)
        #expect(world[Position.self, of: disabled] == position)
        #expect(world.contains(disabled))
    }

    @Test("Updates skip disabled entities unless they allow them or write Disabled")
    func updates() {
        var world = World()
        let enabled = world.spawn(Health(1), Velocity(dx: 0, dy: 0))
        let disabled = world.spawn(Health(1), Velocity(dx: 0, dy: 0), Disabled())
        world.update(Health.self) { health, _ in health.current += 1 }
        world.update(Health.self, reading: Velocity.self) { health, _ in health.current += 10 }
        world.update(Health.self, Velocity.self) { health, _, _ in health.current += 100 }
        let enabledHealth: Health = Health(112)
        let untouched: Health = Health(1)
        #expect(world[Health.self, of: enabled] == enabledHealth)
        #expect(world[Health.self, of: disabled] == untouched)
        world.update(Health.self, where: .allowing(Disabled.self)) { health, _ in health.current += 1000 }
        let allowedHealth: Health = Health(1001)
        #expect(world[Health.self, of: disabled] == allowedHealth)
        var written = 0
        world.update(Disabled.self) { _, _ in written += 1 }
        let expected: Int = 1
        #expect(written == expected)
    }

    @Test("A parallel update skips disabled entities")
    func parallelUpdate() {
        var world = World()
        let enabled = world.spawn(Health(1), Velocity(dx: 0, dy: 0))
        let disabled = world.spawn(Health(1), Velocity(dx: 0, dy: 0), Disabled())
        world.parallelUpdate(Health.self, reading: Velocity.self, minimumChunk: 1) { health, _ in health.current = 7 }
        let changed: Health = Health(7)
        let untouched: Health = Health(1)
        #expect(world[Health.self, of: enabled] == changed)
        #expect(world[Health.self, of: disabled] == untouched)
    }

    @Test("Removing Disabled enables the entity again")
    func reenable() {
        var world = World()
        let entity = world.spawn(Position(x: 0, y: 0), Disabled())
        #expect(world.query(Position.self).count == 0)
        world.remove(Disabled.self, from: entity)
        let expected: Int = 1
        #expect(world.query(Position.self).count == expected)
    }

    @Test("A registered disabling component is skipped like Disabled; registering twice changes nothing")
    func registered() {
        var world = World()
        let enabled = world.spawn(Position(x: 0, y: 0))
        let template = world.spawn(Position(x: 0, y: 0), Template())
        let before: [Entity] = [enabled, template]
        #expect(world.query(Position.self).map(\.entity).sorted() == before)
        world.registerDisablingComponent(Template.self)
        world.registerDisablingComponent(Template.self)
        let after: [Entity] = [enabled]
        #expect(world.query(Position.self).map(\.entity) == after)
        #expect(world.query(Position.self).allowing(Template.self).map(\.entity).sorted() == before)
        world.spawn(Position(x: 0, y: 0), Template(), Disabled())
        #expect(world.query(Position.self).allowing(Template.self).count == 2)
        #expect(world.query(Position.self).allowing(Template.self, Disabled.self).count == 3)
    }

    @Test("The filter types mirror allowing")
    func filterType() {
        let expected: QueryFilter = .allowing(Disabled.self)
        #expect(Allows<Disabled>.filter == expected)
    }

    @Test("Queries match a model of random disabled entities", .tags(.randomized))
    func matchesModel() async {
        let flags = Gen.int(in: 0 ... 3).array(of: 0 ... 40)
        await propertyCheck(count: 200, input: flags) { flags in
            var world = World()
            var expectedSkipping: [Entity] = []
            var expectedAll: [Entity] = []
            for flag in flags {
                let entity = world.spawn(Position(x: 0, y: 0))
                if flag & 1 != 0 { world.insert(Disabled(), into: entity) }
                if flag & 2 != 0 { world.insert(Velocity(dx: 0, dy: 0), into: entity) }
                if flag & 2 != 0 {
                    expectedAll.append(entity)
                    if flag & 1 == 0 { expectedSkipping.append(entity) }
                }
            }
            #expect(world.query(Position.self, Velocity.self).map(\.entity).sorted() == expectedSkipping)
            #expect(world.query(Position.self, Velocity.self).allowing(Disabled.self).map(\.entity).sorted() == expectedAll)
        }
    }
}
