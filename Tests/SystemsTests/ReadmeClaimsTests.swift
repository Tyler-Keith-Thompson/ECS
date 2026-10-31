// Claims the README makes about systems that no other suite pins. Each test is self-contained
// apart from the systems declared at the top of this file.

import ECSTestSupport
import Systems
import Testing
import WorldModule

/// The entities each run of a system saw as new, one list per run.
struct ReadmeAddedRuns: Resource { var runs: [[Entity]] = [] }

/// Records the entities whose Health was added since its last run, through the filter value.
struct ReadmeAddedObserver: System {
    func run(in world: inout World) {
        let added = world.query(Health.self).added(Health.self).map(\.entity).sorted()
        world.resources[ReadmeAddedRuns.self].runs.append(added)
    }
}

/// Records the entities whose Health was added since its last run, through the filter type.
@System
struct ReadmeAddedParameter {
    func run(_ added: Query<Health>.Where<Added<Health>>, _ runs: ResourceWriter<ReadmeAddedRuns>) {
        runs.value.runs.append(added.map(\.entity).sorted())
    }
}

@Suite("README claims: systems")
struct ReadmeClaimsTests {
    @Test("Inside a system, added lists the components added since that system last ran, not the changed ones")
    func addedSinceLastRun() {
        var world = World()
        world.resources.insert(ReadmeAddedRuns())
        let first = world.spawn(Health(1))
        let schedule = Schedule { ReadmeAddedObserver() }
        schedule.run(on: &world)
        world[Health.self, of: first].current = 5
        let second = world.spawn(Health(2))
        schedule.run(on: &world)
        schedule.run(on: &world)
        let expected: [[Entity]] = [[first], [second], []]
        #expect(world.resources[ReadmeAddedRuns.self].runs == expected)
    }

    @Test("An Added filter parameter lists the components added since the system last ran")
    func addedParameterSinceLastRun() {
        var world = World()
        world.resources.insert(ReadmeAddedRuns())
        let first = world.spawn(Health(1))
        let schedule = Schedule { ReadmeAddedParameter() }
        schedule.run(on: &world)
        world[Health.self, of: first].current = 5
        let second = world.spawn(Health(2))
        schedule.run(on: &world)
        schedule.run(on: &world)
        let expected: [[Entity]] = [[first], [second], []]
        #expect(world.resources[ReadmeAddedRuns.self].runs == expected)
    }
}
