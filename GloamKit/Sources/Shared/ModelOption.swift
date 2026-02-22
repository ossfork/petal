import Foundation

public struct ModelDescriptor: Sendable, Equatable {
    public let id: String
    public let repoID: String
    public let name: String
    public let summary: String
    public let size: String
    public let quantization: String
    public let parameters: String
    public let recommended: Bool

    public init(
        id: String,
        repoID: String,
        name: String,
        summary: String,
        size: String,
        quantization: String,
        parameters: String,
        recommended: Bool
    ) {
        self.id = id
        self.repoID = repoID
        self.name = name
        self.summary = summary
        self.size = size
        self.quantization = quantization
        self.parameters = parameters
        self.recommended = recommended
    }
}

public enum ModelOption: String, CaseIterable, Identifiable, Sendable {
    case mini3b = "mini-3b"
    case mini3b8bit = "mini-3b-8bit"
    case mini3b4bit = "mini-3b-4bit"

    // Temporarily expose only the validated model in UI while keeping legacy IDs readable.
    public static var allCases: [ModelOption] { [.mini3b] }
    public static let defaultOption: Self = .mini3b

    public var id: String { rawValue }

    public var descriptor: ModelDescriptor {
        switch self {
        case .mini3b:
            return ModelDescriptor(
                id: rawValue,
                repoID: "mlx-community/Voxtral-Mini-3B-2507-bf16",
                name: "Voxtral Mini 3B (bf16)",
                summary: "Recommended for accurate, on-device transcription.",
                size: "~8.7 GB",
                quantization: "bf16",
                parameters: "3B",
                recommended: true
            )
        case .mini3b8bit:
            return ModelDescriptor(
                id: rawValue,
                repoID: "mlx-community/Voxtral-Mini-3B-2507-bf16",
                name: "Voxtral Mini 3B (Legacy 8-bit Selection)",
                summary: "Automatically mapped to the validated bf16 checkpoint.",
                size: "~8.7 GB",
                quantization: "bf16",
                parameters: "3B",
                recommended: false
            )
        case .mini3b4bit:
            return ModelDescriptor(
                id: rawValue,
                repoID: "mlx-community/Voxtral-Mini-3B-2507-bf16",
                name: "Voxtral Mini 3B (Legacy 4-bit Selection)",
                summary: "Automatically mapped to the validated bf16 checkpoint.",
                size: "~8.7 GB",
                quantization: "bf16",
                parameters: "3B",
                recommended: false
            )
        }
    }

    public var displayName: String {
        descriptor.name
    }

    public var summary: String {
        descriptor.summary
    }

    public var sizeLabel: String {
        descriptor.size
    }

    public var isRecommended: Bool {
        descriptor.recommended
    }

    public static func from(modelID: String) -> Self {
        switch modelID {
        case Self.mini3b.rawValue,
             Self.mini3b8bit.rawValue,
             Self.mini3b4bit.rawValue:
            return .mini3b
        default:
            return .defaultOption
        }
    }
}
