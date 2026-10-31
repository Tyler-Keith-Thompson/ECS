import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct SystemMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [SystemMacro.self]
}

/// `@System`: conforms a type to `System` from its `run` method.
///
/// A `run(in world: inout World)` makes a system that runs alone. A `run` taking system
/// parameters makes a system whose `access` is built from the parameters' types and whose
/// `run(in:)` fetches them, calls `run`, and puts back what they wrote. The macro reads only the
/// signature, never the body.
public struct SystemMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let runs = declaration.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "run" }
        guard let run = runs.first else {
            context.diagnose(Diagnostic(node: node, message: SystemDiagnostic.noRun))
            return []
        }
        guard runs.count == 1 else {
            for extra in runs.dropFirst() {
                context.diagnose(Diagnostic(node: extra.name, message: SystemDiagnostic.severalRuns))
            }
            return []
        }
        guard let signature = check(run, in: context) else { return [] }
        let isolation: Isolation = isMainActor(declaration.attributes) || isMainActor(run.attributes) ? .mainActor : .none
        let extensionDecl: DeclSyntax
        switch signature {
        case .world(let label):
            if label == "in" {
                extensionDecl = "extension \(type.trimmed): \(raw: isolation.conformance) {}"
            } else {
                let call = label == "_" ? "run(&world)" : "run(\(label): &world)"
                extensionDecl = """
                    extension \(type.trimmed): \(raw: isolation.conformance) {
                        \(raw: isolation.runAttribute)public func run(in world: inout World) {
                            \(raw: call)
                        }
                    }
                    """
            }
        case .parameters(let parameters):
            extensionDecl = parameterSystem(type.trimmed, parameters, isolation: isolation)
        }
        guard let result = extensionDecl.as(ExtensionDeclSyntax.self) else { return [] }
        return [result]
    }

    /// What a `run` takes: the world, under an argument label, or system parameters.
    enum Signature {
        case world(label: String)
        case parameters([Parameter])
    }

    /// One system parameter of a `run`.
    struct Parameter {
        let label: String
        let type: TypeSyntax
        let kind: Kind
        /// For an `Update`: its written types and whether it has `Over` terms.
        let written: [String]
        let hasTerms: Bool
        /// The type names the parameter reads, and writes, as written, for spotting conflicts.
        let readNames: [String]
        let writeNames: [String]

        enum Kind {
            case query, update, resourceReader, resourceWriter, eventReader, eventWriter, removedComponents, commands
        }
    }

    /// The signature of `run`, or nil after diagnosing why it cannot make a system.
    static func check(_ run: FunctionDeclSyntax, in context: some MacroExpansionContext) -> Signature? {
        var valid = true
        if let effects = run.signature.effectSpecifiers {
            if let async = effects.asyncSpecifier {
                context.diagnose(Diagnostic(node: async, message: SystemDiagnostic.async))
                valid = false
            }
            if let throwsClause = effects.throwsClause {
                context.diagnose(Diagnostic(node: throwsClause, message: SystemDiagnostic.throwing))
                valid = false
            }
        }
        for modifier in run.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.mutating):
                context.diagnose(Diagnostic(
                    node: modifier, message: SystemDiagnostic.mutating,
                    fixIt: FixIt(message: SystemFixIt.removeMutating, changes: [.replace(oldNode: Syntax(run), newNode: Syntax(removing(modifier, from: run)))])))
                valid = false
            case .keyword(.static), .keyword(.class):
                context.diagnose(Diagnostic(node: modifier, message: SystemDiagnostic.staticRun))
                valid = false
            default:
                break
            }
        }
        let parameters = Array(run.signature.parameterClause.parameters)
        var worldParameters: [FunctionParameterSyntax] = []
        var systemParameters: [Parameter] = []
        for parameter in parameters {
            let (specifier, base) = unwrap(parameter.type)
            let label = parameter.firstName.text
            if baseName(of: base) == "World" {
                worldParameters.append(parameter)
                if specifier != "inout" {
                    context.diagnose(Diagnostic(
                        node: parameter.type, message: SystemDiagnostic.worldNotInout,
                        fixIt: FixIt(message: SystemFixIt.makeInout, changes: [.replace(
                            oldNode: Syntax(parameter.type),
                            newNode: Syntax(TypeSyntax(AttributedTypeSyntax(
                                specifiers: [.simpleTypeSpecifier(SimpleTypeSpecifierSyntax(specifier: .keyword(.inout, trailingTrivia: .space)))],
                                baseType: base.trimmed))))])))
                    valid = false
                }
                continue
            }
            guard let classified = classify(base, label: label) else {
                context.diagnose(Diagnostic(node: parameter.type, message: SystemDiagnostic.notAParameter(base.trimmedDescription)))
                valid = false
                continue
            }
            if specifier == "inout", classified.kind != .commands {
                context.diagnose(Diagnostic(node: parameter.type, message: SystemDiagnostic.inoutParameter))
                valid = false
            }
            if classified.kind == .commands, specifier != "inout" {
                context.diagnose(Diagnostic(
                    node: parameter.type, message: SystemDiagnostic.commandsNotInout,
                    fixIt: FixIt(message: SystemFixIt.makeInout, changes: [.replace(
                        oldNode: Syntax(parameter.type),
                        newNode: Syntax(TypeSyntax(AttributedTypeSyntax(
                            specifiers: [.simpleTypeSpecifier(SimpleTypeSpecifierSyntax(specifier: .keyword(.inout, trailingTrivia: .space)))],
                            baseType: base.trimmed))))])))
                valid = false
            }
            systemParameters.append(classified)
        }
        if !worldParameters.isEmpty {
            if parameters.count > 1 {
                for parameter in worldParameters {
                    context.diagnose(Diagnostic(node: parameter, message: SystemDiagnostic.worldWithParameters))
                }
                return nil
            }
            return valid ? .world(label: worldParameters[0].firstName.text) : nil
        }
        // Conflicts the names show: a type one parameter writes and another reads or writes.
        for (index, parameter) in systemParameters.enumerated() {
            for (otherIndex, other) in systemParameters.enumerated() where otherIndex != index {
                for name in parameter.writeNames where other.writeNames.contains(name) && otherIndex > index
                    || other.readNames.contains(name) {
                    context.diagnose(Diagnostic(node: run.signature.parameterClause, message: SystemDiagnostic.conflict(name)))
                    valid = false
                }
            }
        }
        return valid ? .parameters(systemParameters) : nil
    }

    /// `run` without `modifier`, the modifier's leading trivia kept on what follows it.
    static func removing(_ modifier: DeclModifierSyntax, from run: FunctionDeclSyntax) -> FunctionDeclSyntax {
        var result = run
        let remaining = run.modifiers.filter { $0.id != modifier.id }
        result.modifiers = remaining
        if let index = run.modifiers.firstIndex(where: { $0.id == modifier.id }), index == run.modifiers.startIndex {
            if var first = result.modifiers.first {
                first.leadingTrivia = modifier.leadingTrivia
                result.modifiers = DeclModifierListSyntax([first] + Array(result.modifiers.dropFirst()))
            } else {
                result.funcKeyword.leadingTrivia = modifier.leadingTrivia
            }
        }
        return result
    }

    /// The `inout` or other specifier of `type`, and the type without it.
    static func unwrap(_ type: TypeSyntax) -> (specifier: String?, base: TypeSyntax) {
        guard let attributed = type.as(AttributedTypeSyntax.self) else { return (nil, type) }
        let specifier = attributed.specifiers.first.flatMap { element -> String? in
            if case .simpleTypeSpecifier(let simple) = element { return simple.specifier.text }
            return nil
        }
        return (specifier, attributed.baseType)
    }

    /// The last name of a possibly module-qualified type with no member types: `World` for
    /// `WorldModule.World`.
    static func baseName(of type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) { return identifier.name.text }
        if let member = type.as(MemberTypeSyntax.self), member.genericArgumentClause == nil,
           member.baseType.as(IdentifierTypeSyntax.self)?.genericArgumentClause == nil {
            return member.name.text
        }
        return nil
    }

    /// The segments of a type such as `Update<A>.And<B>.Over<C>`, outermost first, each with its
    /// generic arguments as written. A leading module name is dropped.
    static func segments(of type: TypeSyntax) -> [(name: String, arguments: [String])] {
        func arguments(_ clause: GenericArgumentClauseSyntax?) -> [String] {
            clause?.arguments.map { $0.argument.trimmedDescription } ?? []
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return [(identifier.name.text, arguments(identifier.genericArgumentClause))]
        }
        if let member = type.as(MemberTypeSyntax.self) {
            var base = segments(of: member.baseType)
            if base.count == 1, base[0].arguments.isEmpty, ["Systems", "WorldModule", "ECS"].contains(base[0].name) {
                base = []
            }
            return base + [(member.name.text, arguments(member.genericArgumentClause))]
        }
        return []
    }

    /// The component type names inside written terms or filters: `Wind` and `Current` for
    /// `AnyOf<Wind, Current>`, `Frozen` for `Without<Frozen>`.
    static func componentNames(in arguments: [String]) -> [String] {
        arguments.flatMap { argument -> [String] in
            guard let open = argument.firstIndex(of: "<"), argument.hasSuffix(">") else { return [argument] }
            let inner = argument[argument.index(after: open) ..< argument.index(before: argument.endIndex)]
            var parts: [String] = []
            var depth = 0
            var current = ""
            for character in inner {
                if character == "<" { depth += 1 }
                if character == ">" { depth -= 1 }
                if character == ",", depth == 0 {
                    parts.append(current.trimmingWhitespace())
                    current = ""
                } else {
                    current.append(character)
                }
            }
            parts.append(current.trimmingWhitespace())
            return componentNames(in: parts)
        }
    }

    /// `type` as a system parameter, or nil if it is not one.
    static func classify(_ type: TypeSyntax, label: String) -> Parameter? {
        let parts = segments(of: type)
        guard let first = parts.first else { return nil }
        let rest = parts.dropFirst()
        func make(_ kind: Parameter.Kind, written: [String] = [], hasTerms: Bool = false, reads: [String] = [], writes: [String] = []) -> Parameter {
            Parameter(label: label, type: type.trimmed, kind: kind, written: written, hasTerms: hasTerms, readNames: reads, writeNames: writes)
        }
        switch first.name {
        case "Query":
            guard !first.arguments.isEmpty, rest.count <= 1, rest.allSatisfy({ $0.name == "Where" }) else { return nil }
            return make(.query, reads: componentNames(in: first.arguments + (rest.first?.arguments ?? [])))
        case "Update":
            guard first.arguments.count == 1 else { return nil }
            var written = first.arguments
            var terms: [String] = []
            var filters: [String] = []
            var hasTerms = false
            var stage = 0  // 0: And, 1: Over, 2: Where
            for part in rest {
                switch part.name {
                case "And" where stage == 0 && part.arguments.count == 1 && written.count < 3:
                    written += part.arguments
                case "Over" where stage == 0:
                    terms = part.arguments
                    hasTerms = true
                    stage = 1
                case "Where" where stage < 2:
                    filters = part.arguments
                    stage = 2
                default:
                    return nil
                }
            }
            return make(.update, written: written, hasTerms: hasTerms, reads: componentNames(in: terms + filters), writes: written)
        case "ResourceReader" where rest.isEmpty && first.arguments.count == 1:
            return make(.resourceReader, reads: first.arguments)
        case "ResourceWriter" where rest.isEmpty && first.arguments.count == 1:
            return make(.resourceWriter, writes: first.arguments)
        case "EventReader" where rest.isEmpty && first.arguments.count == 1:
            return make(.eventReader)
        case "EventWriter" where rest.isEmpty && first.arguments.count == 1:
            return make(.eventWriter, writes: ["Events<\(first.arguments[0])>"])
        case "RemovedComponents" where rest.isEmpty && first.arguments.count == 1:
            return make(.removedComponents)
        case "Commands" where rest.isEmpty && first.arguments.isEmpty:
            return make(.commands)
        default:
            return nil
        }
    }

    /// Whether `attributes` include `@MainActor`.
    static func isMainActor(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "MainActor"
        }
    }

    /// The conformance of a system whose `run` takes `parameters`.
    static func parameterSystem(_ type: some TypeSyntaxProtocol, _ parameters: [Parameter], isolation: Isolation) -> DeclSyntax {
        let accesses = parameters.map { "\($0.type)._access(in: Self.self)" }.joined(separator: ", ")
        var fetches: [String] = []
        var restores: [String] = []
        var arguments: [String] = []
        // Writers first, so readers see the world without what they write; event readers mark
        // events read in the world itself.
        let order: [Parameter.Kind] = [.update, .resourceWriter, .eventWriter, .eventReader, .removedComponents, .query, .resourceReader, .commands]
        var names = [String](repeating: "", count: parameters.count)
        for kind in order {
            for (index, parameter) in parameters.enumerated() where parameter.kind == kind {
                let name = "parameter\(index)"
                names[index] = name
                switch kind {
                case .update:
                    if parameter.hasTerms {
                        let written = parameter.written.map { "\($0).self" }.joined(separator: ", ")
                        fetches.append("let \(name) = \(parameter.type)._fetch(from: &world) { world, query, body in world.update(\(written), over: query, body: body) }")
                    } else {
                        fetches.append("let \(name) = \(parameter.type)._fetch(from: &world)")
                    }
                    restores.insert("\(name)._restore(into: &world)", at: 0)
                case .resourceWriter, .eventWriter:
                    fetches.append("let \(name) = \(parameter.type)._fetch(from: &world)")
                    restores.insert("\(name)._restore(into: &world)", at: 0)
                case .eventReader, .removedComponents:
                    fetches.append("let \(name) = \(parameter.type)._fetch(from: &world, system: Self.self)")
                case .query:
                    fetches.append("let \(name) = \(parameter.type)._fetch(from: world) { world, query in world.query(query) }")
                case .resourceReader:
                    fetches.append("let \(name) = \(parameter.type)._fetch(from: world)")
                case .commands:
                    fetches.append("var \(name) = Commands()")
                    restores.append("world.queue(\(name))")
                }
            }
        }
        for (index, parameter) in parameters.enumerated() {
            let value = parameter.kind == .commands ? "&\(names[index])" : names[index]
            arguments.append(parameter.label == "_" ? value : "\(parameter.label): \(value)")
        }
        let body = (fetches + ["run(\(arguments.joined(separator: ", ")))"] + restores)
            .map { "        " + $0 }.joined(separator: "\n")
        let initializations = parameters.filter { $0.kind == .removedComponents }
            .map { "        \($0.type)._initialize(in: &world)" }
        let initialize = initializations.isEmpty ? "" : """


                \(isolation.nonisolatedAttribute)public func initialize(in world: inout World) {
            \(initializations.joined(separator: "\n"))
                }
            """
        return """
            extension \(type): \(raw: isolation.conformance) {
                \(raw: isolation.nonisolatedAttribute)public var access: Access? {
                    _parameterAccess(\(raw: accesses))
                }

                \(raw: isolation.runAttribute)public func run(in world: inout World) {
            \(raw: body)
                }\(raw: initialize)
            }
            """
    }
}

extension String {
    func trimmingWhitespace() -> String {
        var text = Substring(self)
        while text.first?.isWhitespace == true { text.removeFirst() }
        while text.last?.isWhitespace == true { text.removeLast() }
        return String(text)
    }
}

/// Where a system made by `@System` runs.
enum Isolation {
    /// Anywhere: a `System`.
    case none
    /// On the main actor: a `MainActorSystem`.
    case mainActor

    var conformance: String {
        switch self {
        case .none: "System"
        case .mainActor: "MainActorSystem"
        }
    }

    var runAttribute: String {
        switch self {
        case .none: ""
        case .mainActor: "@MainActor "
        }
    }

    var nonisolatedAttribute: String {
        switch self {
        case .none: ""
        case .mainActor: "nonisolated "
        }
    }
}

/// Why `@System` cannot make a system of a type.
enum SystemDiagnostic: DiagnosticMessage {
    case noRun
    case severalRuns
    case async
    case throwing
    case mutating
    case staticRun
    case worldNotInout
    case worldWithParameters
    case notAParameter(String)
    case inoutParameter
    case commandsNotInout
    case conflict(String)

    var message: String {
        switch self {
        case .noRun:
            "@System needs a 'run' method: 'func run(in world: inout World)' or one taking system parameters"
        case .severalRuns:
            "@System needs exactly one 'run' method"
        case .async:
            "A system's 'run' cannot be 'async'"
        case .throwing:
            "A system's 'run' cannot throw"
        case .mutating:
            "A system's 'run' cannot be 'mutating': a system keeps its state in the world"
        case .staticRun:
            "A system's 'run' must be an instance method"
        case .worldNotInout:
            "A system's world must be 'inout'"
        case .worldWithParameters:
            "A 'run' takes either the world or system parameters, not both"
        case .notAParameter(let type):
            "'\(type)' is not a system parameter: use Query, Update, ResourceReader, ResourceWriter, EventReader, EventWriter, RemovedComponents or inout Commands"
        case .inoutParameter:
            "Only Commands is passed 'inout'; parameters that write are reference types"
        case .commandsNotInout:
            "Commands must be 'inout'"
        case .conflict(let type):
            "Two parameters conflict over '\(type)': one writes it and the other reads or writes it"
        }
    }

    var diagnosticID: MessageID {
        let id: String = switch self {
        case .noRun: "noRun"
        case .severalRuns: "severalRuns"
        case .async: "async"
        case .throwing: "throwing"
        case .mutating: "mutating"
        case .staticRun: "staticRun"
        case .worldNotInout: "worldNotInout"
        case .worldWithParameters: "worldWithParameters"
        case .notAParameter: "notAParameter"
        case .inoutParameter: "inoutParameter"
        case .commandsNotInout: "commandsNotInout"
        case .conflict: "conflict"
        }
        return MessageID(domain: "SystemMacros", id: id)
    }

    var severity: DiagnosticSeverity { .error }
}

/// The fixes `@System` offers.
enum SystemFixIt: FixItMessage {
    case removeMutating
    case makeInout

    var message: String {
        switch self {
        case .removeMutating: "Remove 'mutating'"
        case .makeInout: "Add 'inout'"
        }
    }

    var fixItID: MessageID {
        MessageID(domain: "SystemMacros", id: self == .removeMutating ? "removeMutating" : "makeInout")
    }
}
