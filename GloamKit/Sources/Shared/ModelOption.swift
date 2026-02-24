import Foundation

public enum ModelProvider: String, Sendable, Equatable {
    case voxtralCore = "Voxtral Core"
    case mlxAudioSTT = "MLX Audio STT"
}

public struct ModelDescriptor: Sendable, Equatable {
    public let id: String
    public let repoID: String
    public let name: String
    public let summary: String
    public let size: String
    public let quantization: String
    public let parameters: String
    public let provider: ModelProvider
    public let recommended: Bool

    public init(
        id: String,
        repoID: String,
        name: String,
        summary: String,
        size: String,
        quantization: String,
        parameters: String,
        provider: ModelProvider,
        recommended: Bool
    ) {
        self.id = id
        self.repoID = repoID
        self.name = name
        self.summary = summary
        self.size = size
        self.quantization = quantization
        self.parameters = parameters
        self.provider = provider
        self.recommended = recommended
    }
}

public enum ModelOption: String, CaseIterable, Identifiable, Sendable {
    case qwen3ASR06B4bit = "qwen3-asr-0.6b-4bit"
    case mini3b = "mini-3b"
    case mini3b8bit = "mini-3b-8bit"
    case mini3b4bit = "mini-3b-4bit"

    // Keep legacy Voxtral IDs readable while exposing current catalog options in UI.
    public static var allCases: [ModelOption] { [.qwen3ASR06B4bit, .mini3b] }
    public static let defaultOption: Self = .mini3b

    public var id: String { rawValue }

    public var descriptor: ModelDescriptor {
        switch self {
        case .qwen3ASR06B4bit:
            return ModelDescriptor(
                id: rawValue,
                repoID: "mlx-community/Qwen3-ASR-0.6B-4bit",
                name: "Qwen3 ASR 0.6B (4-bit)",
                summary: "Faster, lightweight on-device transcription via MLX Audio STT.",
                size: "~1.2 GB",
                quantization: "4-bit",
                parameters: "0.6B",
                provider: .mlxAudioSTT,
                recommended: false
            )
        case .mini3b:
            return ModelDescriptor(
                id: rawValue,
                repoID: "mlx-community/Voxtral-Mini-3B-2507-bf16",
                name: "Voxtral Mini 3B (bf16)",
                summary: "Recommended for accurate, on-device transcription.",
                size: "~8.7 GB",
                quantization: "bf16",
                parameters: "3B",
                provider: .voxtralCore,
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
                provider: .voxtralCore,
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
                provider: .voxtralCore,
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

    public var provider: ModelProvider {
        descriptor.provider
    }

    public var providerDisplayName: String {
        descriptor.provider.rawValue
    }

    public var isRecommended: Bool {
        descriptor.recommended
    }

    public var supportedTranscriptionModes: [TranscriptionMode] {
        switch self {
        case .qwen3ASR06B4bit:
            return [.verbatim]
        case .mini3b, .mini3b8bit, .mini3b4bit:
            return TranscriptionMode.allCases
        }
    }

    public var supportsSmartTranscription: Bool {
        supportedTranscriptionModes.contains(.smart)
    }

    public func supportsTranscriptionMode(_ mode: TranscriptionMode) -> Bool {
        supportedTranscriptionModes.contains(mode)
    }

    public static func from(modelID: String) -> Self {
        let normalized = modelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case Self.qwen3ASR06B4bit.rawValue,
             "qwen3-asr-0.6b",
             "mlx-community/qwen3-asr-0.6b-4bit":
            return .qwen3ASR06B4bit
        case Self.mini3b.rawValue,
             Self.mini3b8bit.rawValue,
             Self.mini3b4bit.rawValue,
             "mlx-community/voxtral-mini-3b-2507-bf16":
            return .mini3b
        default:
            return .defaultOption
        }
    }
}
