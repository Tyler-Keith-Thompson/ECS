// Writes test sources holding every ```swift block of the documentation, so the examples readers
// copy are compiled and run with the tests.
//
// The arguments are the output files, `--`, then the files to read: Swift sources, whose `///`
// doc comments are searched, and DocC articles (`.md`), searched whole. Each module's
// documentation (everything under `Sources/<Module>/`) and each other file (the README) is a
// namespace, written to the output file of its name (`WorldModule.swift`, `README.swift`).
// Each block becomes one test. Its type declarations and extensions move to the top level of its
// namespace's file, made `fileprivate`, where every other block of the namespace sees them (so a
// module's blocks share types such as a `Position` component, and never declare the same name
// twice); its imports move to the file's imports; the rest is the test's body. A line `print(x)`
// followed by `// Prints "text"`, on the same line or the next, becomes an expectation that `x`
// prints `text`.
//
// Bazel runs this in a genrule (tools/generated_sources.bzl); the checked-in copies under
// Tests/ECSTests/Generated/DocumentationExamples are what SwiftPM compiles, and
// `//Tests/ECSTests:DocumentationExamples_test` fails when they differ. `just sources` refreshes
// them.

import Foundation
import SwiftParser
import SwiftSyntax

/// One ```swift block: where it starts and its lines, without the doc comment's slashes.
struct Example {
    let path: String
    let line: Int
    let lines: [String]
}

/// A line of documentation and its line number in the file.
struct DocumentationLine {
    let number: Int
    let text: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("DocumentationExamples: \(message)\n".utf8))
    exit(1)
}

/// The documentation lines of a file: a Swift source's `///` comment lines with the slashes and
/// one following space removed, or every line of an article.
func documentationLines(of path: String, contents: String) -> [[DocumentationLine]] {
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard path.hasSuffix(".swift") else {
        return [lines.enumerated().map { DocumentationLine(number: $0.offset + 1, text: $0.element) }]
    }
    var comments: [[DocumentationLine]] = []
    var current: [DocumentationLine] = []
    for (offset, line) in lines.enumerated() {
        let trimmed = line.drop { $0 == " " }
        if trimmed.hasPrefix("///") {
            var text = trimmed.dropFirst(3)
            if text.first == " " { text = text.dropFirst() }
            current.append(DocumentationLine(number: offset + 1, text: String(text)))
        } else if !current.isEmpty {
            comments.append(current)
            current = []
        }
    }
    if !current.isEmpty { comments.append(current) }
    return comments
}

/// The ```swift blocks among documentation lines, each dedented by its fence's indentation.
func examples(in path: String, lines: [DocumentationLine]) -> [Example] {
    var found: [Example] = []
    var index = 0
    while index < lines.count {
        let line = lines[index].text
        let indentation = line.prefix { $0 == " " }.count
        let fence = line.dropFirst(indentation)
        guard fence.hasPrefix("```") else {
            index += 1
            continue
        }
        let language = fence.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let start = lines[index].number
        var body: [String] = []
        index += 1
        while index < lines.count, lines[index].text.trimmingCharacters(in: .whitespaces) != "```" {
            body.append(String(lines[index].text.dropFirst(min(indentation, lines[index].text.prefix { $0 == " " }.count))))
            index += 1
        }
        guard index < lines.count else { fail("\(path):\(start): the code block is never closed") }
        index += 1
        if language == "swift" {
            found.append(Example(path: path, line: start, lines: body))
        }
    }
    return found
}

/// An example split into what goes at the file's top level and what goes in its test.
struct SplitExample {
    var imports: [String] = []
    var declarations: [String] = []
    var body: [String] = []
}

func split(_ example: Example) -> SplitExample {
    let source = Parser.parse(source: example.lines.joined(separator: "\n"))
    var result = SplitExample()
    var body = ""
    for statement in source.statements {
        let text = statement.description
        switch statement.item {
        case .decl(let declaration) where declaration.is(ImportDeclSyntax.self):
            result.imports.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case .decl(let declaration) where declaration.isTypeOrExtension:
            result.declarations.append(text.trimmingCharacters(in: .newlines))
        default:
            body += text
        }
    }
    // A comment ending the block belongs to the end of the file, not to any statement.
    body += source.endOfFileToken.leadingTrivia.description
    result.body = expectingPrints(
        in: body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
        of: example
    )
    while result.body.first?.allSatisfy(\.isWhitespace) == true { result.body.removeFirst() }
    while result.body.last?.allSatisfy(\.isWhitespace) == true { result.body.removeLast() }
    return result
}

extension DeclSyntax {
    /// Whether the declaration is a type or an extension, which an example shares with the others.
    var isTypeOrExtension: Bool {
        self.is(StructDeclSyntax.self) || self.is(ClassDeclSyntax.self) || self.is(EnumDeclSyntax.self)
            || self.is(ActorDeclSyntax.self) || self.is(ProtocolDeclSyntax.self)
            || self.is(ExtensionDeclSyntax.self) || self.is(TypeAliasDeclSyntax.self)
    }
}

/// The text of a `// Prints "text"` comment, or nil if the line is not one.
func printedText(_ line: Substring) -> Substring? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let prefix = "// Prints \""
    guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("\""), trimmed.count > prefix.count else { return nil }
    return Substring(trimmed.dropFirst(prefix.count).dropLast())
}

/// The arguments of a line that is exactly one `print(…)` call, or nil.
func printArguments(_ line: Substring) -> Substring? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("print("), trimmed.hasSuffix(")") else { return nil }
    return Substring(trimmed.dropFirst("print(".count).dropLast())
}

/// The body with each `print(x)` that a `// Prints "text"` comment follows replaced by an
/// expectation that `x` prints `text`.
func expectingPrints(in lines: [String], of example: Example) -> [String] {
    var result: [String] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        let indentation = String(line.prefix { $0 == " " })
        if let marker = line.range(of: "// Prints \"") {
            let code = line[..<marker.lowerBound]
            if let arguments = printArguments(code), let text = printedText(line[marker.lowerBound...]) {
                result.append("\(indentation)#expect(printed(\(arguments)) == #\"\(text)\"#)")
                index += 1
                continue
            }
            fail("\(example.path):\(example.line): a `// Prints` comment must follow a one-line print(_:) or end its line")
        }
        if let arguments = printArguments(line[...]), index + 1 < lines.count,
           let text = printedText(lines[index + 1][...]) {
            result.append("\(indentation)#expect(printed(\(arguments)) == #\"\(text)\"#)")
            index += 2
            continue
        }
        result.append(line)
        index += 1
    }
    return result
}

/// The namespace of a file's examples, which names its output file: the module for a source or
/// article under `Sources/<Module>/`, otherwise the file's name (`README`).
func namespace(of path: String) -> String {
    let components = path.split(separator: "/")
    if components.count > 2, components[0] == "Sources" { return String(components[1]) }
    return String(components.last!.split(separator: ".").first!)
}

/// The declaration made `fileprivate`, so each namespace's file can declare the same names as
/// another's. A declaration that already states its access, and an extension declaring a
/// conformance (which takes no access modifier), stay as they are.
func filePrivate(_ text: String) -> String {
    let parsed = Parser.parse(source: text)
    guard parsed.statements.count == 1, case .decl(let declaration) = parsed.statements.first!.item else { return text }
    let accessKeywords: Set<String> = ["private", "fileprivate", "internal", "package", "public", "open"]
    let modifiers: DeclModifierListSyntax
    let keyword: TokenSyntax
    if let type = declaration.as(StructDeclSyntax.self) {
        (modifiers, keyword) = (type.modifiers, type.structKeyword)
    } else if let type = declaration.as(ClassDeclSyntax.self) {
        (modifiers, keyword) = (type.modifiers, type.classKeyword)
    } else if let type = declaration.as(EnumDeclSyntax.self) {
        (modifiers, keyword) = (type.modifiers, type.enumKeyword)
    } else if let type = declaration.as(ActorDeclSyntax.self) {
        (modifiers, keyword) = (type.modifiers, type.actorKeyword)
    } else if let type = declaration.as(ProtocolDeclSyntax.self) {
        (modifiers, keyword) = (type.modifiers, type.protocolKeyword)
    } else if let type = declaration.as(TypeAliasDeclSyntax.self) {
        (modifiers, keyword) = (type.modifiers, type.typealiasKeyword)
    } else if let type = declaration.as(ExtensionDeclSyntax.self), type.inheritanceClause == nil {
        (modifiers, keyword) = (type.modifiers, type.extensionKeyword)
    } else {
        return text
    }
    guard !modifiers.contains(where: { accessKeywords.contains($0.name.text) }) else { return text }
    let next = modifiers.first?.name ?? keyword
    var bytes = Array(text.utf8)
    bytes.insert(contentsOf: Array("fileprivate ".utf8), at: next.positionAfterSkippingLeadingTrivia.utf8Offset)
    return String(decoding: bytes, as: UTF8.self)
}

func indented(_ text: String, by spaces: Int) -> String {
    let indentation = String(repeating: " ", count: spaces)
    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.isEmpty ? "" : indentation + $0 }
        .joined(separator: "\n")
}

/// The test source of one namespace's examples.
func source(of name: String, examples: [(Example, SplitExample)]) -> String {
    let imports = Set(["import ECS", "import Testing"] + examples.flatMap(\.1.imports)).sorted()
    var output = """
        // GENERATED by tools/DocumentationExamples from the ```swift blocks of the \(name) documentation.
        // Edit the documentation, never this file, then run `just sources`.

        \(imports.joined(separator: "\n"))

        /// What `print(_:)` writes for `items`, without the newline.
        private func printed(_ items: Any...) -> String {
            items.map { String(describing: $0) }.joined(separator: " ")
        }

        """
    if imports.contains("import Foundation") {
        output += """

            // Foundation's Bundle would otherwise make the name ambiguous in this file.
            private typealias Bundle = ECS.Bundle

            """
    }
    for (example, split) in examples where !split.declarations.isEmpty {
        output += "\n// \(example.path):\(example.line)\n"
        output += split.declarations.map(filePrivate).joined(separator: "\n\n") + "\n"
    }
    output += """

        @Suite("Examples in the \(name) documentation")
        @MainActor
        struct \(name)DocumentationExamples {
        """
    for (number, (example, split)) in examples.enumerated() {
        let body = indented(split.body.joined(separator: "\n"), by: 8)
        output += """

                @Test("\(example.path):\(example.line)")
                func example\(number + 1)() async throws {
            \(body)
                }

            """
    }
    return output + "}\n"
}

// The arguments: the output files, `--`, then the files to read.
let arguments = Array(CommandLine.arguments.dropFirst())
guard let separator = arguments.firstIndex(of: "--") else { fail("usage: DocumentationExamples <outputs>… -- <inputs>…") }
let outputs = Dictionary(uniqueKeysWithValues: arguments[..<separator].map { path in
    (String(path.split(separator: "/").last!.dropLast(".swift".count)), path)
})
var all: [String: [(Example, SplitExample)]] = [:]
for path in arguments[(separator + 1)...].sorted() {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    for comment in documentationLines(of: path, contents: contents) {
        for example in examples(in: path, lines: comment) {
            all[namespace(of: path), default: []].append((example, split(example)))
        }
    }
}
for name in all.keys where outputs[name] == nil {
    fail("the \(name) documentation has examples but no output file")
}
for (name, path) in outputs {
    let text = source(of: name, examples: all[name] ?? [])
    do {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        fail("cannot write \(path): \(error)")
    }
}
