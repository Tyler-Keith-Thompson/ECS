// System sets: groups of systems ordered, conditioned and checked together. Self-contained.

import ECSTestSupport
import Systems
import Testing
import WorldModule

enum PhysicsSet: SystemSet {}
enum RenderSet: SystemSet {}

struct SetInput: System { func run(in world: inout World) {} }
struct SetGravity: System { func run(in world: inout World) {} }
struct SetCollisions: System { func run(in world: inout World) {} }
struct SetRender: System { func run(in world: inout World) {} }

struct SetVelocityWriter: System {
    var access: Access? { .writes(Velocity.self) }
    func run(in world: inout World) {}
}

struct SetVelocityReader: System {
    var access: Access? { .reads(Velocity.self) }
    func run(in world: inout World) {}
}

/// Logs its tag when it runs.
struct Tagged: System {
    let tag: String
    func run(in world: inout World) { world.resources[Seen.self].values.append(tag.count) }
}

@Suite("Schedule: system sets")
struct SystemSetTests {
    @Test("A system after a set runs after every system in it")
    func afterSet() {
        let schedule = Schedule {
            SetRender().after(PhysicsSet.self)
            SetGravity().inSet(PhysicsSet.self)
            SetCollisions().inSet(PhysicsSet.self)
        }
        let expected: [String] = ["SetGravity", "SetCollisions", "SetRender"]
        #expect(schedule.names == expected)
    }

    @Test("A system before a set runs before every system in it")
    func beforeSet() {
        let schedule = Schedule {
            SetGravity().inSet(PhysicsSet.self)
            SetCollisions().inSet(PhysicsSet.self)
            SetInput().before(PhysicsSet.self)
        }
        let expected: [String] = ["SetInput", "SetGravity", "SetCollisions"]
        #expect(schedule.names == expected)
    }

    @Test("A nested schedule's modifiers configure every system in it")
    func nestedModifiers() {
        let schedule = Schedule {
            SetRender().after(PhysicsSet.self)
            Schedule {
                SetGravity()
                SetCollisions()
            }
            .inSet(PhysicsSet.self)
            .after(SetInput.self)
            SetInput()
        }
        let expected: [String] = ["SetInput", "SetGravity", "SetCollisions", "SetRender"]
        #expect(schedule.names == expected)
    }

    @Test("A schedule's before orders every system in it")
    func scheduleBefore() {
        let schedule = Schedule {
            SetRender()
            Schedule {
                SetGravity()
                SetCollisions()
            }
            .before(SetRender.self)
        }
        let expected: [String] = ["SetGravity", "SetCollisions", "SetRender"]
        #expect(schedule.names == expected)
    }

    @Test("A system type is a set: after a type still means every system of it")
    func typeIsSet() {
        let schedule = Schedule {
            SetRender().after(SetGravity.self)
            SetGravity()
            SetGravity()
        }
        let expected: [String] = ["SetGravity", "SetGravity", "SetRender"]
        #expect(schedule.names == expected)
    }

    @Test("A system can be in several sets")
    func severalSets() {
        let schedule = Schedule {
            SetInput().after(RenderSet.self)
            SetGravity().inSet(PhysicsSet.self, RenderSet.self)
        }
        let expected: [String] = ["SetGravity", "SetInput"]
        #expect(schedule.names == expected)
    }

    @Test("A set with no systems orders nothing")
    func emptySet() {
        let schedule = Schedule {
            SetRender().after(PhysicsSet.self)
            SetGravity()
        }
        let expected: [String] = ["SetRender", "SetGravity"]
        #expect(schedule.names == expected)
    }

    @Test("Constraints through sets that form a cycle throw")
    func cycleThroughSets() {
        let systems: [ScheduledSystem] = [
            SetGravity().inSet(PhysicsSet.self).after(RenderSet.self),
            SetRender().inSet(RenderSet.self).after(PhysicsSet.self),
        ]
        #expect(throws: CyclicOrdering.self) { try Schedule(checked: systems) }
    }

    @Test("A set's ordering puts its systems in later waves")
    func waves() {
        let schedule = Schedule {
            SetVelocityWriter().inSet(PhysicsSet.self)
            SetGravity().inSet(PhysicsSet.self)
            Tagged(tag: "x").after(PhysicsSet.self)
        }
        #expect(schedule.waves.count == 3)
    }

    @Test("Ordering through a set settles an ambiguity; marking a set ambiguous leaves it out")
    func ambiguities() {
        let ordered = Schedule {
            SetVelocityWriter().inSet(PhysicsSet.self)
            SetVelocityReader().after(PhysicsSet.self)
        }
        let marked = Schedule {
            SetVelocityWriter().inSet(PhysicsSet.self)
            SetVelocityReader().ambiguous(with: PhysicsSet.self)
        }
        let unordered = Schedule {
            SetVelocityWriter().inSet(PhysicsSet.self)
            SetVelocityReader()
        }
        #expect(ordered.ambiguities().isEmpty)
        #expect(marked.ambiguities().isEmpty)
        #expect(unordered.ambiguities().count == 1)
    }

    @Test("A condition on a nested schedule skips all of it")
    func conditionedSet() {
        var world = World()
        world.resources.insert(Seen())
        Schedule {
            Tagged(tag: "a")
            Schedule {
                Tagged(tag: "bb")
                Tagged(tag: "ccc")
            }
            .inSet(PhysicsSet.self)
            .runIf { _ in false }
        }.run(on: &world)
        let expected: Seen = Seen(values: [1])
        #expect(world.resources[Seen.self] == expected)
    }
}
