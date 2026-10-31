// swift-tools-version: 6.3
import PackageDescription

// Benchmarks for ECS, kept out of the published package so it does not depend on
// package-benchmark. Run with `just bench` (or `swift package benchmark` in this directory).
let package = Package(
    name: "ECSBenchmarks",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.38.1"),
    ],
    targets: [
        .executableTarget(
            name: "WorldBenchmarks",
            dependencies: [
                .product(name: "WorldModule", package: "ECS"),
                .product(name: "Systems", package: "ECS"),
                .product(name: "Benchmark", package: "package-benchmark"),
            ],
            path: "Benchmarks/WorldBenchmarks",
            plugins: [.plugin(name: "BenchmarkPlugin", package: "package-benchmark")]
        ),
    ]
)
