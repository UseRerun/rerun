// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Rerun",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "rerun", targets: ["RerunCLI"]),
        .executable(name: "rerun-daemon", targets: ["RerunDaemon"]),
        .library(name: "RerunCore", targets: ["RerunCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.2.0")),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "CSQLiteVec",
            dependencies: [],
            cSettings: [
                .define("SQLITE_CORE"),
            ]
        ),
        .target(
            name: "RerunCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "CSQLiteVec",
            ]
        ),
        .executableTarget(
            name: "RerunCLI",
            dependencies: [
                "RerunCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
            ]
        ),
        .executableTarget(
            name: "RerunDaemon",
            dependencies: [
                "RerunCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "RerunCoreTests",
            dependencies: ["RerunCore"]
        ),
        .testTarget(
            name: "RerunCLITests",
            dependencies: ["RerunCLI"]
        ),
        .testTarget(
            name: "RerunDaemonTests",
            dependencies: ["RerunDaemon"]
        ),
    ]
)
