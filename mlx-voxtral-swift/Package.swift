// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MLXVoxtralSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VoxtralCore",
            targets: ["VoxtralCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.30.6"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.30.6")
    ],
    targets: [
        .target(
            name: "VoxtralCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "Transformers", package: "swift-transformers"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm")
            ]
        ),
        .testTarget(
            name: "VoxtralCoreTests",
            dependencies: ["VoxtralCore"]
        )
    ]
)
