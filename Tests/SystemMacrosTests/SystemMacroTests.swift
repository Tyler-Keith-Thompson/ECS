// The @System macro's expansions and diagnostics. Each test is self-contained.

import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import SystemMacros
import Testing

@Suite("@System expansions")
struct SystemMacroExpansionTests {
    @Test("A run taking the world in: conforms with nothing added")
    func worldIn() {
        assertMacroExpansion(
            """
            @System
            struct Loader {
                func run(in world: inout World) {}
            }
            """,
            expandedSource: """
                struct Loader {
                    func run(in world: inout World) {}
                }

                extension Loader: System {
                }
                """,
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A run taking the world unlabeled gets a forwarding run(in:)")
    func worldUnlabeled() {
        assertMacroExpansion(
            """
            @System
            struct Loader {
                func run(_ world: inout World) {}
            }
            """,
            expandedSource: """
                struct Loader {
                    func run(_ world: inout World) {}
                }

                extension Loader: System {
                    public func run(in world: inout World) {
                        run(&world)
                    }
                }
                """,
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A run taking the world under another label forwards with that label")
    func worldOtherLabel() {
        assertMacroExpansion(
            """
            @System
            struct Loader {
                func run(on world: inout WorldModule.World) {}
            }
            """,
            expandedSource: """
                struct Loader {
                    func run(on world: inout WorldModule.World) {}
                }

                extension Loader: System {
                    public func run(in world: inout World) {
                        run(on: &world)
                    }
                }
                """,
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("An update over terms fetches through the update overload for its shape")
    func updateOver() {
        assertMacroExpansion(
            """
            @System
            struct Movement {
                func run(movers: Update<Position>.Over<Velocity>) {}
            }
            """,
            expandedSource: """
                struct Movement {
                    func run(movers: Update<Position>.Over<Velocity>) {}
                }

                extension Movement: System {
                    public var access: Access? {
                        _parameterAccess(Update<Position>.Over<Velocity>._access(in: Self.self))
                    }

                    public func run(in world: inout World) {
                        let parameter0 = Update<Position>.Over<Velocity>._fetch(from: &world) { world, query, body in
                            world.update(Position.self, over: query, body: body)
                        }
                        run(movers: parameter0)
                        parameter0._restore(into: &world)
                    }
                }
                """,
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Writers are fetched before readers and restored in reverse; commands queue last")
    func fetchOrder() {
        assertMacroExpansion(
            """
            @System
            struct Spawner {
                func run(_ query: Query<Position>, score: ResourceWriter<Score>, hits: EventReader<Hit>, commands: inout Commands, log: EventWriter<Logged>, time: ResourceReader<Time>, frozen: Update<Frozen>.And<Tint>) {}
            }
            """,
            expandedSource: """
                struct Spawner {
                    func run(_ query: Query<Position>, score: ResourceWriter<Score>, hits: EventReader<Hit>, commands: inout Commands, log: EventWriter<Logged>, time: ResourceReader<Time>, frozen: Update<Frozen>.And<Tint>) {}
                }

                extension Spawner: System {
                    public var access: Access? {
                        _parameterAccess(Query<Position>._access(in: Self.self), ResourceWriter<Score>._access(in: Self.self), EventReader<Hit>._access(in: Self.self), Commands._access(in: Self.self), EventWriter<Logged>._access(in: Self.self), ResourceReader<Time>._access(in: Self.self), Update<Frozen>.And<Tint>._access(in: Self.self))
                    }

                    public func run(in world: inout World) {
                        let parameter6 = Update<Frozen>.And<Tint>._fetch(from: &world)
                        let parameter1 = ResourceWriter<Score>._fetch(from: &world)
                        let parameter4 = EventWriter<Logged>._fetch(from: &world)
                        let parameter2 = EventReader<Hit>._fetch(from: &world, system: Self.self)
                        let parameter0 = Query<Position>._fetch(from: world) { world, query in
                            world.query(query)
                        }
                        let parameter5 = ResourceReader<Time>._fetch(from: world)
                        var parameter3 = Commands()
                        run(parameter0, score: parameter1, hits: parameter2, commands: &parameter3, log: parameter4, time: parameter5, frozen: parameter6)
                        parameter4._restore(into: &world)
                        parameter1._restore(into: &world)
                        parameter6._restore(into: &world)
                        world.queue(parameter3)
                    }
                }
                """,
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A query with a filter is a parameter of its own")
    func queryWhere() {
        assertMacroExpansion(
            """
            @System
            struct Census {
                func run(_ drifting: Query<Position, AnyOf<Wind, Current>>.Where<Without<Anchored>>) {}
            }
            """,
            expandedSource: """
                struct Census {
                    func run(_ drifting: Query<Position, AnyOf<Wind, Current>>.Where<Without<Anchored>>) {}
                }

                extension Census: System {
                    public var access: Access? {
                        _parameterAccess(Query<Position, AnyOf<Wind, Current>>.Where<Without<Anchored>>._access(in: Self.self))
                    }

                    public func run(in world: inout World) {
                        let parameter0 = Query<Position, AnyOf<Wind, Current>>.Where<Without<Anchored>>._fetch(from: world) { world, query in
                            world.query(query)
                        }
                        run(parameter0)
                    }
                }
                """,
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Removed components are fetched like events and started in initialize")
    func removedComponents() {
        assertMacroExpansion(
            """
            @System
            struct Cleanup {
                func run(_ gone: RemovedComponents<Health>, _ names: Query<Name>) {}
            }
            """,
            expandedSource: """
                struct Cleanup {
                    func run(_ gone: RemovedComponents<Health>, _ names: Query<Name>) {}
                }

                extension Cleanup: System {
                    public var access: Access? {
                        _parameterAccess(RemovedComponents<Health>._access(in: Self.self), Query<Name>._access(in: Self.self))
                    }

                    public func run(in world: inout World) {
                        let parameter0 = RemovedComponents<Health>._fetch(from: &world, system: Self.self)
                        let parameter1 = Query<Name>._fetch(from: world) { world, query in
                            world.query(query)
                        }
                        run(parameter0, parameter1)
                    }

                    public func initialize(in world: inout World) {
                        RemovedComponents<Health>._initialize(in: &world)
                    }
                }
                """,
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A run with no parameters makes a system that accesses nothing")
    func noParameters() {
        assertMacroExpansion(
            """
            @System
            struct Idle {
                func run() {}
            }
            """,
            expandedSource: """
                struct Idle {
                    func run() {}
                }

                extension Idle: System {
                    public var access: Access? {
                        _parameterAccess()
                    }

                    public func run(in world: inout World) {
                        run()
                    }
                }
                """,
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}

@Suite("@System diagnostics")
struct SystemMacroDiagnosticTests {
    @Test("A type without run is diagnosed")
    func noRun() {
        assertMacroExpansion(
            """
            @System
            struct Empty {}
            """,
            expandedSource: """
                struct Empty {}
                """,
            diagnostics: [
                DiagnosticSpec(message: "@System needs a 'run' method: 'func run(in world: inout World)' or one taking system parameters", line: 1, column: 1)
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Two run methods are diagnosed at the second")
    func severalRuns() {
        assertMacroExpansion(
            """
            @System
            struct Twice {
                func run(in world: inout World) {}
                func run(_ query: Query<Position>) {}
            }
            """,
            expandedSource: """
                struct Twice {
                    func run(in world: inout World) {}
                    func run(_ query: Query<Position>) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "@System needs exactly one 'run' method", line: 4, column: 10)
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("An async or throwing run is diagnosed")
    func effects() {
        assertMacroExpansion(
            """
            @System
            struct Effects {
                func run(in world: inout World) async throws {}
            }
            """,
            expandedSource: """
                struct Effects {
                    func run(in world: inout World) async throws {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "A system's 'run' cannot be 'async'", line: 3, column: 37),
                DiagnosticSpec(message: "A system's 'run' cannot throw", line: 3, column: 43),
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A mutating run is diagnosed with a fix that removes mutating")
    func mutatingRun() {
        assertMacroExpansion(
            """
            @System
            struct Counter {
                mutating func run(in world: inout World) {}
            }
            """,
            expandedSource: """
                struct Counter {
                    mutating func run(in world: inout World) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "A system's 'run' cannot be 'mutating': a system keeps its state in the world", line: 3, column: 5,
                    fixIts: [FixItSpec(message: "Remove 'mutating'")])
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            fixedSource: """
                @System
                struct Counter {
                    func run(in world: inout World) {}
                }
                """,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A static run is diagnosed")
    func staticRun() {
        assertMacroExpansion(
            """
            @System
            struct Shared {
                static func run(in world: inout World) {}
            }
            """,
            expandedSource: """
                struct Shared {
                    static func run(in world: inout World) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "A system's 'run' must be an instance method", line: 3, column: 5)
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A world not passed inout is diagnosed with a fix that adds inout")
    func worldNotInout() {
        assertMacroExpansion(
            """
            @System
            struct Reader {
                func run(in world: World) {}
            }
            """,
            expandedSource: """
                struct Reader {
                    func run(in world: World) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "A system's world must be 'inout'", line: 3, column: 24,
                    fixIts: [FixItSpec(message: "Add 'inout'")])
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            fixedSource: """
                @System
                struct Reader {
                    func run(in world: inout World) {}
                }
                """,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A run taking the world and parameters is diagnosed")
    func worldWithParameters() {
        assertMacroExpansion(
            """
            @System
            struct Mixed {
                func run(in world: inout World, _ query: Query<Position>) {}
            }
            """,
            expandedSource: """
                struct Mixed {
                    func run(in world: inout World, _ query: Query<Position>) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "A 'run' takes either the world or system parameters, not both", line: 3, column: 14)
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A parameter of another type is diagnosed, naming the type")
    func notAParameter() {
        assertMacroExpansion(
            """
            @System
            struct Odd {
                func run(count: Int) {}
            }
            """,
            expandedSource: """
                struct Odd {
                    func run(count: Int) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "'Int' is not a system parameter: use Query, Update, ResourceReader, ResourceWriter, EventReader, EventWriter, RemovedComponents or inout Commands", line: 3, column: 21)
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("An update with more than three written types is not a parameter")
    func updateFourWrites() {
        assertMacroExpansion(
            """
            @System
            struct Wide {
                func run(_ all: Update<A>.And<B>.And<C>.And<D>) {}
            }
            """,
            expandedSource: """
                struct Wide {
                    func run(_ all: Update<A>.And<B>.And<C>.And<D>) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "'Update<A>.And<B>.And<C>.And<D>' is not a system parameter: use Query, Update, ResourceReader, ResourceWriter, EventReader, EventWriter, RemovedComponents or inout Commands", line: 3, column: 21)
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A parameter other than Commands passed inout is diagnosed")
    func inoutParameter() {
        assertMacroExpansion(
            """
            @System
            struct Writer {
                func run(score: inout ResourceWriter<Score>) {}
            }
            """,
            expandedSource: """
                struct Writer {
                    func run(score: inout ResourceWriter<Score>) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "Only Commands is passed 'inout'; parameters that write are reference types", line: 3, column: 21)
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Commands not passed inout is diagnosed with a fix that adds inout")
    func commandsNotInout() {
        assertMacroExpansion(
            """
            @System
            struct Spawner {
                func run(commands: Commands) {}
            }
            """,
            expandedSource: """
                struct Spawner {
                    func run(commands: Commands) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Commands must be 'inout'", line: 3, column: 24,
                    fixIts: [FixItSpec(message: "Add 'inout'")])
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            fixedSource: """
                @System
                struct Spawner {
                    func run(commands: inout Commands) {}
                }
                """,
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("Two parameters writing one type are diagnosed once")
    func writeWriteConflict() {
        assertMacroExpansion(
            """
            @System
            struct Doubled {
                func run(_ first: Update<Position>, _ second: Update<Position>.Over<Velocity>) {}
            }
            """,
            expandedSource: """
                struct Doubled {
                    func run(_ first: Update<Position>, _ second: Update<Position>.Over<Velocity>) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "Two parameters conflict over 'Position': one writes it and the other reads or writes it", line: 3, column: 13)
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }

    @Test("A query reading a type another parameter writes is diagnosed, inside AnyOf too")
    func readWriteConflict() {
        assertMacroExpansion(
            """
            @System
            struct Tangled {
                func run(_ movers: Update<Wind>, _ drifting: Query<Position, AnyOf<Wind, Current>>) {}
            }
            """,
            expandedSource: """
                struct Tangled {
                    func run(_ movers: Update<Wind>, _ drifting: Query<Position, AnyOf<Wind, Current>>) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "Two parameters conflict over 'Wind': one writes it and the other reads or writes it", line: 3, column: 13)
            ],
            macroSpecs: ["System": MacroSpec(type: SystemMacro.self)],
            failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
        )
    }
}
