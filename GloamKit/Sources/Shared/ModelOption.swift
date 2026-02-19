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

    public static let defaultOption: Self = .mini3b8bit

    public var id: String { rawValue }

    public var descriptor: ModelDescriptor {
        switch self {
        case .mini3b:
            return ModelDescriptor(
                id: rawValue,
                repoID: "Aayush9029/Voxtral-Mini-3B-2507",
                name: "Voxtral Mini 3B (Official)",
                summary: "Official Mistral model - full precision",
                size: "~6 GB",
                quantization: "float16",
                parameters: "3B",
                recommended: false
            )
        case .mini3b8bit:
            return ModelDescriptor(
                id: rawValue,
                repoID: "Aayush9029/voxtral-mini-3b-8bit",
                name: "Voxtral Mini 3B (8-bit)",
                summary: "Best quality/size balance for the mini model",
                size: "~3.5 GB",
                quantization: "8-bit",
                parameters: "3B",
                recommended: true
            )
        case .mini3b4bit:
            return ModelDescriptor(
                id: rawValue,
                repoID: "Aayush9029/voxtral-mini-3b-4bit-mixed",
                name: "Voxtral Mini 3B (4-bit mixed)",
                summary: "Smaller footprint, slightly lower quality",
                size: "~2 GB",
                quantization: "4-bit mixed",
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
        self == .defaultOption
    }

    public static func from(modelID: String) -> Self {
        Self(rawValue: modelID) ?? .defaultOption
    }
}
