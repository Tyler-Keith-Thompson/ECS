#!/usr/bin/env python3
"""The module graph, written once.

Package.swift, swift/Package.swift, every Sources/*/BUILD.bazel and Tests/*/BUILD.bazel, the
umbrella module and tools/performance_tests.bzl are generated from the tables below, so SwiftPM
and Bazel cannot drift. Run `just modules` after editing them. `//:package_swift_test` fails when
Package.swift disagrees with the Bazel graph.

Modules are named after the concept they hold, with a `Module` suffix only where the module
would otherwise share a name with its main type (`GreetingModule` would hold `Greeting`). No
catch-all modules ("Core", "Utilities").
"""

import os

# The package, umbrella module and test-support module take the project's name.
PROJECT = "ECS"
TEST_SUPPORT = f"{PROJECT}TestSupport"

# External packages: (identity, url, minimum version). A dependency written "identity/Product"
# in the tables below refers to a product of one of these. After adding one: `just modules`,
# add `swiftpkg_<identity>` (hyphens as underscores) to use_repo in MODULE.bazel, `just resolve`.
PACKAGES = [
    # Tests only: property checks with shrinking, for Swift Testing.
    ("swift-property-based", "https://github.com/x-sheep/swift-property-based", "2.0.1"),
    # Graphs and their algorithms (the owner's library): ordering a schedule's systems and drawing its graph.
    ("grafluent", "https://github.com/Tyler-Keith-Thompson/Grafluent", "0.0.61"),
    # Macros: the compiler plugins in MACROS, and their tests.
    ("swift-syntax", "https://github.com/swiftlang/swift-syntax", "603.0.0"),
    # Mocks generated from protocols (`@Mockable`). Uncomment when a module first needs one; see
    # MOCKING below.
    # ("mockable", "https://github.com/Kolos65/Mockable", "0.6.4"),
]

# The product whose macro generates mocks. A module that depends on it is compiled with the
# MOCKING condition in debug builds only (SwiftPM's debug configuration, Bazel's
# --compilation_mode=dbg), so `@Mockable` emits Mock<Protocol> types for tests and release
# builds carry none.
MOCKING = "mockable/Mockable"

# (name, group, description, dependencies)
MODULES = [
    # Storage
    ("WorldModule", "Storage", "World: entities, their components and resources, with queries, in-place updates and deferred commands.", []),
    # Scheduling
    ("Systems", "Scheduling", "System and Schedule: rules that run on a world, ordered as written unless constrained otherwise.", ["WorldModule", "SystemMacros", "grafluent/Traversal", "grafluent/GraphProtocols", "grafluent/AdjacencyListModule", "grafluent/DirectedAcyclicGraphModule", "grafluent/GraphOperations", "grafluent/GraphFormats"]),
    ("SimulationModule", "Scheduling", "Simulation: a world and its schedules by label, stepped frame by frame with a fixed timestep and states.", ["WorldModule", "Systems"]),
]

# Compiler plugins holding macros: (name, group, description, dependencies). A module lists one
# among its dependencies to use its macros: SwiftPM takes it as a dependency, Bazel as a plugin.
# Not part of the umbrella or the docs.
MACROS = [
    ("SystemMacros", "Scheduling", "The @System macro: a system's access and run(in:) from its run's parameters.", [
        "swift-syntax/SwiftSyntax", "swift-syntax/SwiftSyntaxBuilder", "swift-syntax/SwiftSyntaxMacros",
        "swift-syntax/SwiftCompilerPlugin", "swift-syntax/SwiftDiagnostics",
    ]),
]

# The README, and the umbrella's and every library module's Swift sources and DocC articles (the
# `documentation` filegroup each module's BUILD.bazel declares).
DOCUMENTATION = ["//:readme"] + [f"//Sources/{name}:documentation" for name in [PROJECT] + [m[0] for m in MODULES]]

# Sources a generator writes at build time: {module or test target: [(name, generator label,
# input labels, output names)]}. Bazel compiles the generator's output; SwiftPM compiles the
# checked-in copy at <target directory>/Generated/<name>.swift (or, given output names,
# Generated/<name>/<output>.swift for each), which `just sources` refreshes and <name>_test keeps
# honest (tools/generated_sources.bzl). The generator gets the inputs' paths as arguments.
GENERATED_SOURCES = {
    "WorldModule": [("QueryShapes", "//tools/QueryShapes", [], [])],
    # The documentation's ```swift blocks, compiled and run as tests: one source per module, and
    # one for the README.
    f"{PROJECT}Tests": [(
        "DocumentationExamples", "//tools/DocumentationExamples", DOCUMENTATION,
        ["README", PROJECT] + [m[0] for m in MODULES],
    )],
}

# Test targets. SwiftPM rejects a target with no sources, so list a target only once its directory
# holds tests. (name, dependencies)
TEST_TARGETS = [
    ("WorldModuleTests", ["WorldModule", TEST_SUPPORT, "swift-property-based/PropertyBased"]),
    ("SystemsTests", ["Systems", "WorldModule", TEST_SUPPORT, "swift-property-based/PropertyBased"]),
    ("SimulationModuleTests", ["SimulationModule", "Systems", "WorldModule", TEST_SUPPORT, "swift-property-based/PropertyBased"]),
    ("SystemMacrosTests", ["SystemMacros", "swift-syntax/SwiftSyntax", "swift-syntax/SwiftSyntaxMacros", "swift-syntax/SwiftSyntaxMacroExpansion", "swift-syntax/SwiftSyntaxMacrosGenericTestSupport"]),
    (f"{PROJECT}Tests", [PROJECT]),
]

# The modules the test-support target depends on (fixtures are usually written against the
# vocabulary module). Empty is fine.
TEST_SUPPORT_DEPENDENCIES = ["WorldModule"]

# Bazel test sizes above the default "small" (60 s timeout), for suites whose solo run takes more
# than about 15 s on a laptop or 30 s on a four-core CI runner, and so can pass 60 s when other
# tests load the machine. "medium" is 300 s.
TEST_SIZES = {name: "medium" for name in [
]}

# Test targets whose speed-reliant tests live in Performance/ under the target's directory: tests
# that pass only if the code is fast enough, because they bound their own wall-clock time
# (ContinuousClock) or run a large or adversarial input under a `.timeLimit` meant to catch a
# complexity regression. Each is built as a target of its own, performance_target(name), with the
# same dependencies, in the same Bazel package. `--config=release` builds and runs only those:
# every other test target and test library is tagged RELEASE_EXCLUDED_TAG, which .bazelrc filters
# out under release. Debug runs both. A `.timeLimit` that only guards a small input against a hang
# does not make a test speed-reliant.
PERFORMANCE_TESTS = [
    "WorldModuleTests",
]

# Performance tests run up to their one-minute limits each, so their targets get "medium" (300 s).
PERFORMANCE_TEST_SIZE = "medium"

# The tag .bazelrc's release config filters out of builds and tests (see PERFORMANCE_TESTS).
RELEASE_EXCLUDED_TAG = "debug-only"

# Keep in step with .bazelrc's --macos_minimum_os.
PLATFORMS = '[.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)]'
MACOS_MINIMUM = "15.0"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def performance_target(name):
    """The speed-reliant target split from test target `name`: FlowsTests -> FlowsPerformanceTests."""
    return name.removesuffix("Tests") + "PerformanceTests"


def check():
    names = [m[0] for m in MODULES] + [m[0] for m in MACROS]
    assert len(names) == len(set(names)), "duplicate module"
    assert PROJECT not in names, f"{PROJECT} is the umbrella; it is not listed in MODULES"
    packages = [p[0] for p in PACKAGES]
    for name, _, _, deps in MODULES + MACROS:
        for d in deps:
            if "/" in d:
                assert d.split("/")[0] in packages, f"{name} depends on unknown package {d}"
            else:
                assert d in names, f"{name} depends on unknown {d}"
    tests = [t[0] for t in TEST_TARGETS]
    assert len(tests) == len(set(tests)), "duplicate test target"
    for name, deps in TEST_TARGETS:
        for d in deps:
            if "/" in d:
                assert d.split("/")[0] in packages, f"{name} depends on unknown package {d}"
            else:
                assert d in names + [PROJECT, TEST_SUPPORT], f"{name} depends on unknown {d}"
    for name in GENERATED_SOURCES:
        assert name in names + tests, f"GENERATED_SOURCES names unknown module or test target {name}"
        assert name not in PERFORMANCE_TESTS and name not in macro_test_targets(), f"GENERATED_SOURCES cannot feed {name}"
    for name in PERFORMANCE_TESTS:
        assert name in tests, f"PERFORMANCE_TESTS names unknown test target {name}"


def spm_dep(d):
    if "/" in d:
        package, product = d.split("/")
        return f'.product(name: "{product}", package: "{package}")'
    return f'"{d}"'


def bazel_label(d):
    if "/" in d:
        package, product = d.split("/")
        return f"@swiftpkg_{package.replace('-', '_')}//:{product}"
    if d == TEST_SUPPORT:
        return f"//Tests/{TEST_SUPPORT}"
    return f"//Sources/{d}"


def excluded(path):
    """Non-source files SwiftPM would otherwise warn about, for the target at `path`."""
    return [f for f in ("BUILD.bazel", "README.md", "Performance") if os.path.exists(os.path.join(ROOT, path, f))]


def exclude_arg(path):
    files = excluded(path)
    if files == ["BUILD.bazel"]:
        return ", exclude: bazelFiles"
    if files:
        return ", exclude: [" + ", ".join(f'"{f}"' for f in files) + "]"
    return ""


def package_swift():
    lines = [
        "// swift-tools-version: 6.3",
        "import CompilerPluginSupport",
        "import PackageDescription",
        "",
        "// GENERATED by scripts/modules.py — edit the table there, then run `just modules`.",
        "//",
        "// The published package definition. Bazel is the development build system; both are generated",
        "// from the same table, and `just verify` builds and tests with both.",
        "",
        "// Every target directory holds a BUILD.bazel, which SwiftPM must be told to ignore.",
        'let bazelFiles = ["BUILD.bazel"]',
        "",
        "// Typed arrays of their own: as one `Package(...)` expression, a large manifest is too big for",
        "// the type checker.",
        "let products: [Product] = [",
        f'    .library(name: "{PROJECT}", targets: ["{PROJECT}"]),',
    ]
    lines += [f'    .library(name: "{m[0]}", targets: ["{m[0]}"]),' for m in MODULES]
    lines += ["]", "", "let dependencies: [Package.Dependency] = ["]
    lines += [f'    .package(url: "{url}", from: "{version}"),' for _, url, version in PACKAGES]
    lines += ["]", "", "let targets: [Target] = ["]
    group = None
    for name, g, _, deps in MODULES:
        if g != group:
            lines.append(f"    // {g}")
            group = g
        ex = exclude_arg(f"Sources/{name}")
        settings = ', swiftSettings: [.define("MOCKING", .when(configuration: .debug))]' if MOCKING in deps else ""
        if deps:
            dl = ", ".join(spm_dep(d) for d in deps)
            lines.append(f'    .target(name: "{name}", dependencies: [{dl}]{ex}{settings}),')
        else:
            lines.append(f'    .target(name: "{name}"{ex}),')
    for name, g, _, deps in MACROS:
        lines.append(f"    // {g}: compiler plugin")
        dl = ", ".join(spm_dep(d) for d in deps)
        lines.append(f'    .macro(name: "{name}", dependencies: [{dl}]{exclude_arg(f"Sources/{name}")}),')
    all_deps = ", ".join(f'"{m[0]}"' for m in MODULES)
    support_deps = ", ".join(spm_dep(d) for d in TEST_SUPPORT_DEPENDENCIES)
    support_deps_arg = f"dependencies: [{support_deps}], " if TEST_SUPPORT_DEPENDENCIES else ""
    lines += [
        "",
        f"    // Umbrella: `import {PROJECT}` imports every module.",
        f'    .target(name: "{PROJECT}", dependencies: [{all_deps}], exclude: bazelFiles),',
        "",
        "    // Shared fixtures (data only) for every test target.",
        f'    .target(name: "{TEST_SUPPORT}", {support_deps_arg}path: "Tests/{TEST_SUPPORT}", exclude: bazelFiles),',
        "",
    ]
    for name, deps in TEST_TARGETS:
        dl = ", ".join(spm_dep(d) for d in deps)
        files = excluded(f"Tests/{name}")
        ex = "[" + ", ".join(f'"{f}"' for f in files) + "]" if files != ["BUILD.bazel"] else "bazelFiles"
        lines.append(f'    .testTarget(name: "{name}", dependencies: [{dl}], exclude: {ex}),')
    if PERFORMANCE_TESTS:
        lines += [
            "",
            "    // Speed-reliant tests, split from the target of the same module (PERFORMANCE_TESTS in scripts/modules.py).",
        ]
        for name, deps in TEST_TARGETS:
            if name in PERFORMANCE_TESTS:
                dl = ", ".join(spm_dep(d) for d in deps)
                lines.append(f'    .testTarget(name: "{performance_target(name)}", dependencies: [{dl}], path: "Tests/{name}/Performance"),')
    lines += [
        "]",
        "",
        "let package = Package(",
        f'    name: "{PROJECT}",',
        "    // Keep in step with .bazelrc's --macos_minimum_os.",
        f"    platforms: {PLATFORMS},",
        "    products: products,",
        "    dependencies: dependencies,",
        "    targets: targets",
        ")",
        "",
    ]
    return "\n".join(lines)


def dependency_manifest():
    deps = "".join(f'        .package(url: "{url}", from: "{version}"),\n' for _, url, version in PACKAGES)
    return (
        "// swift-tools-version: 6.0\n"
        "import PackageDescription\n\n"
        "// GENERATED by scripts/modules.py. Dependency-resolution manifest for Bazel\n"
        "// (rules_swift_package_manager); it lists the same packages as the root Package.swift.\n"
        "// After changing it, run `just resolve`.\n"
        "let package = Package(\n"
        f'    name: "{PROJECT}Dependencies",\n'
        f'    platforms: [.macOS("{MACOS_MINIMUM}")],\n'
        f"    dependencies: [\n{deps}    ]\n"
        ")\n"
    )


def is_macro(d):
    return d in [m[0] for m in MACROS]


def generated_parts(name):
    """The load, the generated_swift_source rules and the srcs of the target `name`."""
    generated = GENERATED_SOURCES.get(name, [])
    if not generated:
        return "", "", 'glob(["**/*.swift"])'
    load = 'load("//tools:generated_sources.bzl", "generated_swift_source")\n'
    rules = ""
    for source, generator, inputs, outs in generated:
        inputs_attr = "    srcs = [\n" + "".join(f'        "{i}",\n' for i in inputs) + "    ],\n" if inputs else ""
        outs_attr = "    outs = [\n" + "".join(f'        "{o}",\n' for o in outs) + "    ],\n" if outs else ""
        copy = f"Generated/{source}/" if outs else f"Generated/{source}.swift"
        rules += (
            f"# {copy} is SwiftPM's copy; Bazel compiles the generator's output.\n"
            f'generated_swift_source(\n    name = "{source}",\n    generator = "{generator}",\n{inputs_attr}{outs_attr}'
            f'    tags = ["{RELEASE_EXCLUDED_TAG}"],\n)\n\n'
        )
    srcs = 'glob(["**/*.swift"], exclude = ["Generated/**"], allow_empty = True) + [' + ", ".join(f'":{source}"' for source, _, _, _ in generated) + "]"
    return load, rules, srcs


def build_bazel(name, description, deps):
    plugins = [d for d in deps if is_macro(d)]
    deps = [d for d in deps if not is_macro(d)]
    dl = "".join(f'        "{bazel_label(d)}",\n' for d in deps)
    deps_attr = f"    deps = [\n{dl}    ],\n" if deps else ""
    pl = "".join(f'        "{bazel_label(d)}",\n' for d in plugins)
    deps_attr += f"    plugins = [\n{pl}    ],\n" if plugins else ""
    defines_attr = (
        "    # Mock<Protocol> types from @Mockable, in debug builds only (MOCKING in scripts/modules.py).\n"
        '    defines = select({"//tools:debug": ["MOCKING"], "//conditions:default": []}),\n'
    ) if MOCKING in deps else ""
    doc_deps = "".join(f'        "{bazel_label(d)}:{d}Documentation",\n' for d in deps if "/" not in d)
    doc_deps_attr = f"    deps = [\n{doc_deps}    ],\n" if doc_deps else ""
    generated_load, generated_rules, srcs = generated_parts(name)
    return (
        "# GENERATED by scripts/modules.py — edit the table there, then run `just modules`.\n\n"
        'load("//tools:docc.bzl", "docc_archive")\n'
        f"{generated_load}"
        'load("//tools:swift_rules.bzl", "swift_library")\n\n'
        f"{generated_rules}"
        f"# {description}\n"
        "swift_library(\n"
        f'    name = "{name}",\n'
        f"    srcs = {srcs},\n"
        f'    module_name = "{name}",\n'
        f"{defines_attr}"
        f"{deps_attr}"
        '    visibility = ["//visibility:public"],\n'
        ")\n\n"
        f"# The sources and articles whose ```swift blocks //Tests/{PROJECT}Tests compiles and runs.\n"
        "filegroup(\n"
        '    name = "documentation",\n'
        '    srcs = glob(["**/*.swift", "*.docc/**/*.md"], exclude = ["Generated/**"]),\n'
        '    visibility = ["//Tests:__subpackages__"],\n'
        ")\n\n"
        "# The module's DocC archive, merged into //:docs. `manual` keeps it out of `bazel build //...`.\n"
        "docc_archive(\n"
        f'    name = "{name}Documentation",\n'
        f'    module = ":{name}",\n'
        '    catalog = glob(["*.docc/**"], allow_empty = True),\n'
        f"{doc_deps_attr}"
        '    tags = ["manual"],\n'
        '    visibility = ["//visibility:public"],\n'
        ")\n"
    )


def macro_build_bazel(name, description, deps):
    dl = "".join(f'        "{bazel_label(d)}",\n' for d in deps)
    return (
        "# GENERATED by scripts/modules.py — edit the table there, then run `just modules`.\n\n"
        'load("//tools:swift_rules.bzl", "swift_compiler_plugin")\n\n'
        f"# {description}\n"
        "swift_compiler_plugin(\n"
        f'    name = "{name}",\n'
        '    srcs = glob(["**/*.swift"]),\n'
        f'    module_name = "{name}",\n'
        f"    deps = [\n{dl}    ],\n"
        '    visibility = ["//visibility:public"],\n'
        ")\n"
    )


def macro_test_targets():
    """Test targets that depend on a compiler plugin, which only a swift_test can depend on."""
    return [name for name, deps in TEST_TARGETS if any(is_macro(d) for d in deps)]


def macros_bzl():
    packages = "".join(f'    "Sources/{name}",\n' for name, _, _, _ in MACROS)
    tests = "".join(f'    "Tests/{name}",\n' for name in macro_test_targets())
    return (
        '"""GENERATED by scripts/modules.py (MACROS) — edit the table there, then run `just modules`."""\n\n'
        "# The source packages that hold compiler plugins, which have no documentation of their own.\n"
        f"MACRO_PACKAGES = [\n{packages}]\n\n"
        "# The test packages whose tests depend on a compiler plugin: a lone swift_test each, since a\n"
        "# library cannot depend on a plugin, so neither an Xcode bundle nor a `Library` target.\n"
        f"MACRO_TEST_PACKAGES = [\n{tests}]\n"
    )


def macro_test_build_bazel(name, deps):
    dl = "".join(f'        "{bazel_label(d)}",\n' for d in deps)
    return (
        "# GENERATED by scripts/modules.py — edit the table there, then run `just modules`.\n\n"
        'load("//tools:swift_rules.bzl", "swift_test")\n\n'
        "# Tests of a compiler plugin: only a swift_test can depend on one, so the tests build into it\n"
        f"# directly. Tagged `{RELEASE_EXCLUDED_TAG}`: none relies on speed.\n"
        "swift_test(\n"
        f'    name = "{name}",\n'
        f'    size = "{TEST_SIZES.get(name, "small")}",\n'
        '    srcs = glob(["**/*.swift"]),\n'
        f'    module_name = "{name}",\n'
        f'    tags = ["{RELEASE_EXCLUDED_TAG}"],\n'
        "    # Read by //:package_swift_test, which checks Package.swift against the Bazel graph.\n"
        '    visibility = ["//:__pkg__"],\n'
        f"    deps = [\n{dl}    ],\n"
        ")\n"
    )


def test_support_build_bazel():
    dl = "".join(f'        "{bazel_label(d)}",\n' for d in TEST_SUPPORT_DEPENDENCIES)
    deps_attr = f"    deps = [\n{dl}    ],\n" if TEST_SUPPORT_DEPENDENCIES else ""
    return (
        "# GENERATED by scripts/modules.py — edit TEST_SUPPORT_DEPENDENCIES there, then run `just modules`.\n\n"
        'load("//tools:swift_rules.bzl", "swift_library")\n\n'
        "# Shared fixtures for every test target: data and generators only, no assertion helpers.\n"
        "swift_library(\n"
        f'    name = "{TEST_SUPPORT}",\n'
        "    testonly = True,\n"
        '    srcs = glob(["**/*.swift"]),\n'
        f'    module_name = "{TEST_SUPPORT}",\n'
        f"{deps_attr}"
        '    visibility = ["//visibility:public"],\n'
        ")\n"
    )


def test_targets_bazel(name, deps, size, srcs, tags):
    """One test module: its library, the swift_test that `bazel test` runs, and the Xcode bundle."""
    dl = "".join(f'        "{bazel_label(d)}",\n' for d in deps)
    tags_attr = f"    tags = {tags},\n".replace("'", '"') if tags else ""
    return (
        "swift_library(\n"
        f'    name = "{name}Library",\n'
        "    testonly = True,\n"
        "    # Tests are found through metadata the linker would otherwise drop, since nothing\n"
        "    # references them by name.\n"
        "    alwayslink = True,\n"
        f"    srcs = {srcs},\n"
        f'    module_name = "{name}",\n'
        f"{tags_attr}"
        "    # Read by //:package_swift_test, which checks Package.swift against the Bazel graph.\n"
        '    visibility = ["//:__pkg__"],\n'
        f"    deps = [\n{dl}    ],\n"
        ")\n\n"
        "# `bazel test` / `just test`: a standalone executable, fast to start and run in Bazel's sandbox.\n"
        "swift_test(\n"
        f'    name = "{name}",\n'
        f'    size = "{size}",\n'
        f"{tags_attr}"
        f'    deps = [":{name}Library"],\n'
        ")\n\n"
        "# The generated Xcode project: a real .xctest bundle (an MH_BUNDLE), which is what Xcode's test\n"
        "# runner loads. `manual` keeps it out of `bazel test //...`; it runs through xcodebuild, so it\n"
        "# is only for Xcode. XCTest refuses exit tests in a sandboxed host, hence `no-sandbox`.\n"
        "macos_unit_test(\n"
        f'    name = "{name}Bundle",\n'
        f'    bundle_name = "{name}",\n'
        f'    size = "{size}",\n'
        f'    minimum_os_version = "{MACOS_MINIMUM}",\n'
        '    tags = ["manual", "no-sandbox"],\n'
        "    # Visible so `//:xcodeproj` can name it as a top-level target.\n"
        '    visibility = ["//visibility:public"],\n'
        f'    deps = [":{name}Library"],\n'
        ")\n"
    )


def test_build_bazel(name, deps):
    size = TEST_SIZES.get(name, "small")
    header = (
        "# GENERATED by scripts/modules.py — edit the table there, then run `just modules`.\n\n"
        'load("@rules_apple//apple:macos.bzl", "macos_unit_test")\n'
        'load("//tools:swift_rules.bzl", "swift_library", "swift_test")\n\n'
    )
    excluded_note = (
        f"Tagged `{RELEASE_EXCLUDED_TAG}`: none of these relies on speed, so\n"
        "# `--config=release` neither builds nor runs them (.bazelrc).\n"
    )
    if name not in PERFORMANCE_TESTS:
        generated_load, generated_rules, srcs = generated_parts(name)
        return (header.replace('load("//tools:swift_rules.bzl"', generated_load + 'load("//tools:swift_rules.bzl"')
                + generated_rules + "# The tests, built once and linked into two runners.\n# " + excluded_note
                + test_targets_bazel(name, deps, size, srcs, [RELEASE_EXCLUDED_TAG]))
    return (
        header
        + "# The tests, built once and linked into two runners; the speed-reliant ones, in Performance/, are\n"
        + f"# {performance_target(name)} below. " + excluded_note
        + test_targets_bazel(name, deps, size, 'glob(["**/*.swift"], exclude = ["Performance/**"])', [RELEASE_EXCLUDED_TAG])
        + "\n# The speed-reliant tests (PERFORMANCE_TESTS in scripts/modules.py): debug and `--config=release`\n"
        + "# both run them.\n"
        + test_targets_bazel(performance_target(name), deps, PERFORMANCE_TEST_SIZE, 'glob(["Performance/**/*.swift"])', [])
    )


def performance_tests_bzl():
    packages = "".join(f'    "Tests/{name}",\n' for name in PERFORMANCE_TESTS)
    return (
        '"""GENERATED by scripts/modules.py (PERFORMANCE_TESTS) — edit the list there, then run `just modules`."""\n\n'
        "# The test packages that also hold a speed-reliant target, `<Name>PerformanceTests` built from\n"
        "# Performance/, which the root BUILD.bazel cannot find from the directory layout alone.\n"
        f"PERFORMANCE_TEST_PACKAGES = [\n{packages}]\n"
    )


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def main():
    check()
    for name, _, description, deps in MODULES:
        d = os.path.join(ROOT, "Sources", name)
        write(os.path.join(d, "BUILD.bazel"), build_bazel(name, description, deps))
        # SwiftPM and Bazel both reject a module with no sources. Until a module has real
        # sources, it carries a file holding only its description.
        if not any(fn.endswith(".swift") for _, _, fns in os.walk(d) for fn in fns):
            write(os.path.join(d, f"{name}.swift"), f"// {name}: {description}\n")
    for name, _, description, deps in MACROS:
        write(os.path.join(ROOT, "Sources", name, "BUILD.bazel"), macro_build_bazel(name, description, deps))
    write(os.path.join(ROOT, "tools", "macros.bzl"), macros_bzl())
    for name, deps in TEST_TARGETS:
        d = os.path.join(ROOT, "Tests", name)
        if name in macro_test_targets():
            write(os.path.join(d, "BUILD.bazel"), macro_test_build_bazel(name, deps))
            continue
        write(os.path.join(d, "BUILD.bazel"), test_build_bazel(name, deps))
        # SwiftPM rejects a target with no sources, and one left out of PERFORMANCE_TESTS would be
        # compiled into the module's own target, which release skips.
        performance = os.path.join(d, "Performance")
        has_performance = any(fn.endswith(".swift") for _, _, fns in os.walk(performance) for fn in fns)
        assert has_performance == (name in PERFORMANCE_TESTS), \
            f"{name}: Performance/ holds Swift sources exactly when the target is in PERFORMANCE_TESTS"
    write(os.path.join(ROOT, "Tests", TEST_SUPPORT, "BUILD.bazel"), test_support_build_bazel())
    write(os.path.join(ROOT, "tools", "performance_tests.bzl"), performance_tests_bzl())
    names = [m[0] for m in MODULES]
    umbrella = os.path.join(ROOT, "Sources", PROJECT)
    write(os.path.join(umbrella, "BUILD.bazel"), build_bazel(PROJECT, f"Umbrella: `import {PROJECT}` imports every module.", names))
    write(os.path.join(umbrella, f"{PROJECT}.swift"),
          f"// GENERATED by scripts/modules.py.\n//\n// Umbrella: `import {PROJECT}` imports every module.\n\n"
          + "".join(f"@_exported import {n}\n" for n in names))
    write(os.path.join(ROOT, "swift", "Package.swift"), dependency_manifest())
    # Written last: which files each target must exclude depends on the BUILD files above.
    write(os.path.join(ROOT, "Package.swift"), package_swift())


if __name__ == "__main__":
    main()
