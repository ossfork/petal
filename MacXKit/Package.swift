// swift-tools-version: 6.2

import PackageDescription

extension Target.Dependency {
    static let macXShared: Self = "MacXShared"
    static let macXModels: Self = "MacXModels"
    static let macXUI: Self = "MacXUI"
    static let macXMLXClient: Self = "MacXMLXClient"
    static let macXModelSetupClient: Self = "MacXModelSetupClient"
    static let macXPermissionsClient: Self = "MacXPermissionsClient"

    static let dependencies: Self = .product(name: "Dependencies", package: "swift-dependencies")
    static let dependenciesMacros: Self = .product(name: "DependenciesMacros", package: "swift-dependencies")
    static let sharing: Self = .product(name: "Sharing", package: "swift-sharing")
    static let identifiedCollections: Self = .product(name: "IdentifiedCollections", package: "swift-identified-collections")
    static let keyboardShortcuts: Self = .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
    static let sauce: Self = .product(name: "Sauce", package: "Sauce")
    static let voxtralCore: Self = .product(name: "VoxtralCore", package: "MLXVoxtralSwift")
}

let package = Package(
    name: "MacXKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MacXShared", targets: ["MacXShared"]),
        .library(name: "MacXModels", targets: ["MacXModels"]),
        .library(name: "MacXUI", targets: ["MacXUI"]),
        .library(name: "MacXOnboarding", targets: ["MacXOnboarding"]),
        .library(name: "MacXAudioClient", targets: ["MacXAudioClient"]),
        .library(name: "MacXPermissionsClient", targets: ["MacXPermissionsClient"]),
        .library(name: "MacXPasteClient", targets: ["MacXPasteClient"]),
        .library(name: "MacXKeyboardClient", targets: ["MacXKeyboardClient"]),
        .library(name: "MacXFloatingCapsuleClient", targets: ["MacXFloatingCapsuleClient"]),
        .library(name: "MacXMLXClient", targets: ["MacXMLXClient"]),
        .library(name: "MacXModelSetupClient", targets: ["MacXModelSetupClient"]),
        .library(name: "MacXTranscriptionClient", targets: ["MacXTranscriptionClient"])
    ],
    dependencies: [
        .package(name: "MLXVoxtralSwift", path: "../Vendor/mlx-voxtral-swift"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing.git", from: "2.7.4"),
        .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.3.0"),
        .package(url: "https://github.com/Clipy/Sauce.git", from: "2.4.1")
    ],
    targets: [
        .target(
            name: "MacXShared",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .sharing,
                .identifiedCollections,
                .keyboardShortcuts
            ]
        ),
        .target(
            name: "MacXModels",
            dependencies: [
                .macXShared,
                .macXPermissionsClient,
                .dependencies,
                .dependenciesMacros,
                .sharing,
                .keyboardShortcuts
            ]
        ),
        .target(
            name: "MacXUI",
            dependencies: [
                .macXModels,
                .macXShared,
                .keyboardShortcuts
            ]
        ),
        .target(
            name: "MacXOnboarding",
            dependencies: [
                .macXUI,
                .macXModels,
                .macXShared
            ]
        ),
        .target(
            name: "MacXAudioClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros
            ]
        ),
        .target(
            name: "MacXPermissionsClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros
            ]
        ),
        .target(
            name: "MacXPasteClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .sauce
            ]
        ),
        .target(
            name: "MacXKeyboardClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros
            ]
        ),
        .target(
            name: "MacXFloatingCapsuleClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .macXUI
            ]
        ),
        .target(
            name: "MacXMLXClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .voxtralCore
            ]
        ),
        .target(
            name: "MacXModelSetupClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .macXShared,
                .macXMLXClient
            ]
        ),
        .target(
            name: "MacXTranscriptionClient",
            dependencies: [
                .dependencies,
                .dependenciesMacros,
                .macXShared,
                .macXModelSetupClient,
                .macXMLXClient
            ]
        ),
        .testTarget(
            name: "MacXKitTests",
            dependencies: [
                .macXShared,
                .macXModels,
                .macXUI,
                .macXPermissionsClient,
                "MacXAudioClient",
                "MacXPasteClient",
                "MacXKeyboardClient",
                "MacXFloatingCapsuleClient",
                "MacXMLXClient",
                "MacXModelSetupClient",
                "MacXTranscriptionClient",
                .dependencies
            ]
        )
    ]
)
