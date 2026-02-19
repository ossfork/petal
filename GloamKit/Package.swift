// swift-tools-version: 6.2

import PackageDescription

extension Target.Dependency {
    static let shared: Self = "Shared"
    static let models: Self = "GloamModels"
    static let ui: Self = "UI"
    static let mlxClient: Self = "MLXClient"
    static let audioTrimClient: Self = "AudioTrimClient"
    static let audioSpeedClient: Self = "AudioSpeedClient"
    static let permissionsClient: Self = "PermissionsClient"
    static let downloadClient: Self = "DownloadClient"

    static let dependencies: Self = .product(name: "Dependencies", package: "swift-dependencies")
    static let dependenciesMacros: Self = .product(name: "DependenciesMacros", package: "swift-dependencies")
    static let sharing: Self = .product(name: "Sharing", package: "swift-sharing")
    static let identifiedCollections: Self = .product(name: "IdentifiedCollections", package: "swift-identified-collections")
    static let keyboardShortcuts: Self = .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
    static let sauce: Self = .product(name: "Sauce", package: "Sauce")
    static let voxtralCore: Self = .product(name: "VoxtralCore", package: "MLXVoxtralSwift")
}

let package = Package(
    name: "GloamKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "GloamModels", targets: ["GloamModels"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "Onboarding", targets: ["Onboarding"]),
        .library(name: "AudioClient", targets: ["AudioClient"]),
        .library(name: "PermissionsClient", targets: ["PermissionsClient"]),
        .library(name: "PasteClient", targets: ["PasteClient"]),
        .library(name: "KeyboardClient", targets: ["KeyboardClient"]),
        .library(name: "FloatingCapsuleClient", targets: ["FloatingCapsuleClient"]),
        .library(name: "MLXClient", targets: ["MLXClient"]),
        .library(name: "AudioTrimClient", targets: ["AudioTrimClient"]),
        .library(name: "AudioSpeedClient", targets: ["AudioSpeedClient"]),
        .library(name: "TranscriptionClient", targets: ["TranscriptionClient"]),
        .library(name: "DownloadClient", targets: ["DownloadClient"]),
        .library(name: "HistoryClient", targets: ["HistoryClient"]),
        .library(name: "SoundClient", targets: ["SoundClient"]),
        .library(name: "LogClient", targets: ["LogClient"]),
    ],
    dependencies: [
        .package(name: "MLXVoxtralSwift", path: "../mlx-voxtral-swift"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing.git", from: "2.7.4"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/Clipy/Sauce.git", from: "2.4.1"),
    ],
    targets: [
        .target(
            name: "Shared",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .sharing,
                .identifiedCollections,
                .keyboardShortcuts,
            ]
        ),
        .target(
            name: "GloamModels",
            dependencies: [
                .shared,
                .permissionsClient,
            ]
        ),
        .target(
            name: "UI",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "Onboarding",
            dependencies: [.shared, .models, .ui, .downloadClient, .permissionsClient]
        ),

        // MARK: - Clients

        .target(
            name: "AudioClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "PermissionsClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "PasteClient",
            dependencies: [
                .shared,
                .sauce,
            ]
        ),
        .target(
            name: "KeyboardClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "FloatingCapsuleClient",
            dependencies: [
                .shared,
                .ui,
            ]
        ),
        .target(
            name: "MLXClient",
            dependencies: [
                .shared,
                .voxtralCore,
            ]
        ),
        .target(
            name: "AudioTrimClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "AudioSpeedClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "TranscriptionClient",
            dependencies: [
                .shared,
                .audioTrimClient,
                .audioSpeedClient,
                .mlxClient,
            ]
        ),
        .target(
            name: "DownloadClient",
            dependencies: [
                .shared,
                .mlxClient,
            ]
        ),
        .target(
            name: "HistoryClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "SoundClient",
            dependencies: [
                .shared,
            ]
        ),
        .target(
            name: "LogClient",
            dependencies: [
                .shared,
            ]
        ),
        .testTarget(
            name: "GloamKitTests",
            dependencies: [
                .shared,
                .models,
                .ui,
                .permissionsClient,
                "AudioClient",
                "PasteClient",
                "KeyboardClient",
                "FloatingCapsuleClient",
                "AudioTrimClient",
                "AudioSpeedClient",
                "MLXClient",
                "TranscriptionClient",
                "DownloadClient",
                "HistoryClient",
                "SoundClient",
                "LogClient",
            ]
        ),
    ]
)
