import Foundation
import VoxtralCore

enum ModelOption: String, CaseIterable, Identifiable, Sendable {
    case mini3b = "mini-3b"
    case mini3b8bit = "mini-3b-8bit"
    case mini3b4bit = "mini-3b-4bit"

    static let defaultOption: Self = .mini3b8bit

    var id: String { rawValue }

    var modelInfo: VoxtralModelInfo {
        if let info = ModelRegistry.model(withId: rawValue) {
            return info
        }

        switch self {
        case .mini3b:
            return VoxtralModelInfo(
                id: rawValue,
                repoId: "Aayush9029/Voxtral-Mini-3B-2507",
                name: "Voxtral Mini 3B (Official)",
                description: "Official Mistral model - full precision",
                size: "~6 GB",
                quantization: "float16",
                parameters: "3B"
            )
        case .mini3b8bit:
            return VoxtralModelInfo(
                id: rawValue,
                repoId: "Aayush9029/voxtral-mini-3b-8bit",
                name: "Voxtral Mini 3B (8-bit)",
                description: "Best quality/size balance for the mini model",
                size: "~3.5 GB",
                quantization: "8-bit",
                parameters: "3B",
                recommended: true
            )
        case .mini3b4bit:
            return VoxtralModelInfo(
                id: rawValue,
                repoId: "Aayush9029/voxtral-mini-3b-4bit-mixed",
                name: "Voxtral Mini 3B (4-bit mixed)",
                description: "Smaller footprint, slightly lower quality",
                size: "~2 GB",
                quantization: "4-bit mixed",
                parameters: "3B"
            )
        }
    }

    var displayName: String {
        modelInfo.name
    }

    var summary: String {
        modelInfo.description
    }

    var sizeLabel: String {
        modelInfo.size
    }

    var isRecommended: Bool {
        self == .defaultOption
    }

    var pipelineModel: VoxtralPipeline.Model {
        switch self {
        case .mini3b:
            return .mini3b
        case .mini3b8bit:
            return .mini3b8bit
        case .mini3b4bit:
            return .mini3b4bit
        }
    }

    static func from(modelID: String) -> Self {
        Self(rawValue: modelID) ?? .defaultOption
    }
}
