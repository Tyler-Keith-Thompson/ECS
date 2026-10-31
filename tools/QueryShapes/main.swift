// Writes WorldModule's fixed-arity query and update overloads to standard output.
//
// Swift does not specialize code generic over a parameter pack, so a query whose shape is known
// at the call site gets an overload of its own: every query of one to three terms, each term a
// component or an `AnyOf` of two to four components, for `query(_:)` and for `update` writing
// one, two or three types. Bazel runs this in a genrule (tools/generated_sources.bzl); the
// checked-in copy under Sources/WorldModule/Generated is what SwiftPM compiles, and
// `//Sources/WorldModule:QueryShapes_test` fails when the two differ. `just sources` refreshes it.

/// One term of a query shape: a component, or an `AnyOf` of `count` components.
enum Term {
    case component
    case anyOf(count: Int)
}

/// The largest number of terms, and the sizes of `AnyOf` groups, that get an overload.
let maximumTerms = 3
let anyOfSizes = 2 ... 4

let termKinds: [Term] = [.component] + anyOfSizes.map { Term.anyOf(count: $0) }

/// Every shape of one to `maximumTerms` terms, shortest first.
let shapes: [[Term]] = (1 ... maximumTerms).flatMap { length in
    (0 ..< length).reduce([[]]) { partial, _ in
        partial.flatMap { prefix in termKinds.map { prefix + [$0] } }
    }
}

/// The names one shape's code uses for its type parameters and values.
struct Shape {
    let terms: [Term]

    /// The component type parameters of term `index`: `T0` for a component, `T0_0`, `T0_1`, …
    /// for an `AnyOf`.
    func parameters(of index: Int) -> [String] {
        switch terms[index] {
        case .component: ["T\(index)"]
        case .anyOf(let count): (0 ..< count).map { "T\(index)_\($0)" }
        }
    }

    /// Every component type parameter, in order.
    var allParameters: [String] { terms.indices.flatMap(parameters(of:)) }

    /// The type of term `index`.
    func type(of index: Int) -> String {
        switch terms[index] {
        case .component: "T\(index)"
        case .anyOf: "AnyOf<\(parameters(of: index).joined(separator: ", "))>"
        }
    }

    /// The value type of term `index`.
    func valueType(of index: Int) -> String {
        switch terms[index] {
        case .component: "T\(index)"
        case .anyOf: "(" + parameters(of: index).map { "\($0)?" }.joined(separator: ", ") + ")"
        }
    }

    var types: String { terms.indices.map(type(of:)).joined(separator: ", ") }
    var valueTypes: String { terms.indices.map(valueType(of:)).joined(separator: ", ") }
    var metatypes: String { terms.indices.map { "\(type(of: $0)).self" }.joined(separator: ", ") }
    var values: String { terms.indices.map { "v\($0)" }.joined(separator: ", ") }
    var genericParameters: String { allParameters.map { "\($0): Component" }.joined(separator: ", ") }
    var reads: String { "[" + allParameters.map { "ObjectIdentifier(\($0).self)" }.joined(separator: ", ") + "]" }
    var isComponentsOnly: Bool {
        terms.allSatisfy { if case .component = $0 { true } else { false } }
    }
    /// What a row's components hold: the single value for one term, else a tuple.
    var rowComponents: String { terms.count == 1 ? "v0" : "(\(values))" }
}

func reader(_ shape: Shape) -> String {
    var componentTerms: [Int] = []
    for index in shape.terms.indices {
        if case .component = shape.terms[index] { componentTerms.append(index) }
    }
    var lines: [String] = []
    let parameters = shape.terms.indices.map { "_: \(shape.type(of: $0)).Type" }.joined(separator: ", ")
    let makeTypes = (["Entity"] + shape.terms.indices.map(shape.valueType(of:))).joined(separator: ", ")
    lines.append("    @inlinable")
    lines.append("    func reader<\(shape.genericParameters), Row>(")
    lines.append("        \(parameters), make: @escaping (\(makeTypes)) -> Row")
    lines.append("    ) -> Reader<Row> {")
    for parameter in shape.allParameters {
        lines.append("        let s\(parameter.dropFirst()) = snapshot(of: \(parameter).self)")
    }
    let types = componentTerms.map { "ObjectIdentifier(T\($0).self)" }.joined(separator: ", ")
    let columns = componentTerms.map { "s\($0).index.dense" }.joined(separator: ", ")
    lines.append("        return Reader(types: [\(types)], columns: [\(columns)]) { entity, cursor, driver in")
    var arguments: [String] = []
    for index in shape.terms.indices {
        switch shape.terms[index] {
        case .component:
            let column = componentTerms.firstIndex(of: index)!
            lines.append("            let p\(index): Int")
            lines.append("            if driver == \(column) || driver == alignedDriver { p\(index) = cursor } else {")
            lines.append("                guard let found = s\(index).index.position(of: entity) else { return nil }")
            lines.append("                p\(index) = found")
            lines.append("            }")
            arguments.append("s\(index).values[p\(index)]")
        case .anyOf:
            let names = shape.parameters(of: index).map { $0.dropFirst() }
            for name in names {
                lines.append("            let p\(name) = s\(name).index.position(of: entity)")
            }
            lines.append("            guard " + names.map { "p\($0) != nil" }.joined(separator: " || ") + " else { return nil }")
            arguments.append("(" + names.map { "p\($0).map { s\($0).values[$0] }" }.joined(separator: ", ") + ")")
        }
    }
    lines.append("            return make(entity, \(arguments.joined(separator: ", ")))")
    lines.append("        }")
    lines.append("    }")
    return lines.joined(separator: "\n")
}

func query(_ shape: Shape) -> String {
    """
        /// Returns the entities that match a query of this shape, with the values of its terms.
        ///
        /// A specialization of `query(_:)` for this exact shape of query, chosen by overload
        /// resolution; it lists the same rows.
        @_documentation(visibility: internal)
        @inlinable
        public func query<\(shape.genericParameters)>(_ query: Query<\(shape.types)>) -> QueryView<\(shape.valueTypes)> {
            QueryView(world: self, filter: query.filter) { world in
                world.reader(\(shape.metatypes)) { entity, \(shape.values) in (entity: entity, \(shape.values)) }
            }
        }
    """
}

func update(_ shape: Shape, writing count: Int) -> String {
    let written = (0 ..< count).map { "W\($0)" }
    let generics = written.map { "\($0): Component" }.joined(separator: ", ")
    let metatypes = written.map { "_: \($0).Type" }.joined(separator: ", ")
    let inouts = written.map { "inout \($0)" }.joined(separator: ", ")
    let writtenSelf = written.map { "\($0).self" }.joined(separator: ", ")
    return """
        /// Changes components of every entity that matches a query of this shape, in place.
        ///
        /// A specialization of `update(_:over:body:)` for this exact shape of query and number of
        /// changed types, chosen by overload resolution; it visits the same entities.
        @_documentation(visibility: internal)
        @inlinable
        public mutating func update<\(generics), \(shape.genericParameters), Failure: Error>(
            \(metatypes),
            over query: Query<\(shape.types)>,
            body: (\(inouts), QueryRow<\(shape.valueTypes)>) throws(Failure) -> Void
        ) throws(Failure) {
            try update(
                \(writtenSelf), reads: \(shape.reads),
                reader: { world in world.reader(\(shape.metatypes)) { entity, \(shape.values) in QueryRow<\(shape.valueTypes)>(entity: entity, components: \(shape.rowComponents)) } },
                filter: query.filter, body: body)
        }
    """
}

var output = """
// GENERATED by tools/QueryShapes — do not edit. Run `just sources` to refresh this copy.
//
// Fixed-arity overloads of `World.query(_:)` and `World.update(_:over:body:)` for queries of one
// to \(maximumTerms) terms, each a component or an `AnyOf` of \(anyOfSizes.lowerBound) to \(anyOfSizes.upperBound) components, and the readers
// they use. Queries of only components use the readers in Reader.swift.

extension World {

"""
let all = shapes.map(Shape.init(terms:))
output += all.filter { !$0.isComponentsOnly }.map(reader).joined(separator: "\n\n") + "\n}\n\nextension World {\n"
for shape in all {
    output += query(shape) + "\n\n"
    for count in 1 ... 3 {
        output += update(shape, writing: count) + "\n\n"
    }
}
output.removeLast()
output += "}\n"
print(output, terminator: "")
