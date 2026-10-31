PROJECT_ROOT := justfile_directory()
BAZEL := "bazel"

# Optimized builds use a separate output base: switching --compilation_mode changes the
# configuration, and sharing a base with debug builds would discard the analysis cache on every
# switch (which .bazelrc refuses).
BAZEL_RELEASE := "bazel --output_base=" + home_directory() + "/Library/Caches/bazel-ecs-release"

# SwiftPM runs through Xcode's default toolchain. A development snapshot selected through
# TOOLCHAINS (or first on PATH via swiftly) can fail to read the SDK's Testing module.
SWIFT := "env -u TOOLCHAINS xcrun --toolchain default swift"

[doc('Build everything (default)')]
all: build

[doc('Build every target')]
build:
    {{BAZEL}} build //...

[doc('Run every test')]
test:
    {{BAZEL}} test //...

[doc('Run one test target, e.g. just test-one //Tests/WorldModuleTests')]
test-one target:
    {{BAZEL}} test {{target}}

[doc('Run tests matching a filter, e.g. just filter Query')]
filter pattern:
    {{BAZEL}} test //... --test_filter={{pattern}}

[doc('Run the speed-reliant tests (the PerformanceTests targets) optimized (-O); the rest run in debug only')]
test-release:
    {{BAZEL_RELEASE}} test --config=release //...

[doc('Re-resolve SwiftPM dependencies for Bazel after editing PACKAGES in scripts/modules.py')]
resolve:
    cd {{PROJECT_ROOT}}/swift && {{SWIFT}} package resolve

[doc('Build via SwiftPM too, to verify the published package')]
spm:
    {{SWIFT}} build

[doc('Run the tests via SwiftPM')]
spm-test *args="":
    {{SWIFT}} test {{args}}

[doc('Verify both build systems agree — run before pushing')]
verify: test spm-test

[doc('Run the benchmarks (package-benchmark, in Benchmarks/), e.g. just bench --filter "query.*"')]
bench *args="":
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package benchmark {{args}}

[doc('Record the benchmarks as a named baseline, e.g. just bench-baseline main')]
bench-baseline name:
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package --allow-writing-to-package-directory benchmark baseline update {{name}}

[doc('Compare the benchmarks against a named baseline, e.g. just bench-compare main')]
bench-compare name:
    cd {{PROJECT_ROOT}}/Benchmarks && {{SWIFT}} package benchmark baseline compare {{name}}

[doc('Regenerate Package.swift and every BUILD.bazel from scripts/modules.py')]
modules:
    python3 {{PROJECT_ROOT}}/scripts/modules.py

[doc('Refresh the checked-in copies of generated sources (GENERATED_SOURCES in scripts/modules.py) that SwiftPM compiles')]
sources:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{PROJECT_ROOT}}
    targets=$({{BAZEL}} query 'attr(generator_function, generated_swift_source, kind(genrule, //Sources/... + //Tests/...))')
    {{BAZEL}} build $targets
    for target in $targets; do
        package="${target#//}"; package="${package%%:*}"
        for output in $({{BAZEL}} cquery "$target" --output=files 2>/dev/null); do
            copy="$package/Generated/${output#*/bin/$package/}"
            mkdir -p "$(dirname "$copy")"
            install -m 644 "$output" "$copy"
        done
    done

[doc('Build the combined DocC site for every library module into .build/docs (what the DocC workflow publishes)')]
docs:
    {{BAZEL}} build //:docs
    rm -rf {{PROJECT_ROOT}}/.build/docs && mkdir -p {{PROJECT_ROOT}}/.build
    cp -RL {{PROJECT_ROOT}}/bazel-bin/docs {{PROJECT_ROOT}}/.build/docs && chmod -R u+w {{PROJECT_ROOT}}/.build/docs

[doc('Generate an Xcode project from the Bazel graph and open it')]
generate *args="":
    @bash scripts/generate-xcodeproj.sh {{args}}

[doc('Build optimized: the library and the speed-reliant tests, not the debug-only test targets')]
release:
    {{BAZEL_RELEASE}} build --config=release //...

[doc('Remove all build artifacts')]
clean:
    {{BAZEL}} clean
    {{BAZEL_RELEASE}} clean || true
    rm -rf {{PROJECT_ROOT}}/.build

[doc('Print the dependency graph of a target')]
deps target="//Sources/ECS":
    {{BAZEL}} query 'deps({{target}})' --output=label_kind

[doc('List every buildable target')]
targets:
    {{BAZEL}} query '//...' --output=label_kind

# The checkout of ProjectTemplate this project came from; .template.json records the commit.
PROJECT_TEMPLATE := env("PROJECT_TEMPLATE", home_directory() / "workspace" / "ProjectTemplate")

[doc('Merge the project template’s changes since .template.json’s commit into this checkout (needs a clean worktree), e.g. just template-update, or just template-update --to <commit>')]
template-update *args="":
    python3 {{PROJECT_TEMPLATE}}/template.py update {{PROJECT_ROOT}} {{args}}
