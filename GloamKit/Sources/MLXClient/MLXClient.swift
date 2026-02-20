import Dependencies
import DependenciesMacros
import Foundation
import VoxtralCore

public struct MLXModelInfo: Sendable, Equatable {
    public var id: String
    public var repoId: String
    public var name: String
    public var summary: String
    public var size: String
    public var quantization: String
    public var parameters: String
    public var recommended: Bool

    public init(
        id: String,
        repoId: String,
        name: String,
        summary: String,
        size: String,
        quantization: String,
        parameters: String,
        recommended: Bool
    ) {
        self.id = id
        self.repoId = repoId
        self.name = name
        self.summary = summary
        self.size = size
        self.quantization = quantization
        self.parameters = parameters
        self.recommended = recommended
    }
}

public enum MLXPipelineModel: String, Sendable {
    case mini3b
    case mini3b8bit
    case mini3b4bit
}

public enum MLXTranscriptionMode: Sendable {
    case verbatim
    case smart(prompt: String)
}

@DependencyClient
public struct MLXClient: Sendable {
    public var isModelDownloaded: @Sendable (MLXModelInfo) -> Bool = { _ in false }
    public var downloadModel: @Sendable (MLXModelInfo, @escaping @Sendable (Double, String) -> Void) async throws -> Void
    public var prepareModelIfNeeded: @Sendable (MLXPipelineModel) async throws -> Void
    public var transcribe: @Sendable (URL, MLXTranscriptionMode) async throws -> String
    public var unloadModel: @Sendable () async -> Void = {}
}

extension MLXClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = LiveMLXRuntime()
        return Self(
            isModelDownloaded: { info in
                ModelDownloader.findModelPath(for: info.voxtralModelInfo) != nil
            },
            downloadModel: { info, progress in
                _ = try await ModelDownloader.download(info.voxtralModelInfo, progress: progress)
            },
            prepareModelIfNeeded: { model in
                try await runtime.prepareModelIfNeeded(model: model)
            },
            transcribe: { audioURL, mode in
                try await runtime.transcribe(audioURL: audioURL, mode: mode)
            },
            unloadModel: {
                await runtime.unloadModel()
            }
        )
    }
}

extension MLXClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            isModelDownloaded: { _ in false },
            downloadModel: { _, _ in },
            prepareModelIfNeeded: { _ in },
            transcribe: { _, _ in "Test transcription" },
            unloadModel: {}
        )
    }
}

public extension DependencyValues {
    var mlxClient: MLXClient {
        get { self[MLXClient.self] }
        set { self[MLXClient.self] = newValue }
    }
}

private actor LiveMLXRuntime {
    private var pipeline: VoxtralPipeline?
    private var loadedModel: MLXPipelineModel?

    func prepareModelIfNeeded(model: MLXPipelineModel) async throws {
        if loadedModel == model, pipeline != nil {
            return
        }

        unloadModel()

        var config = VoxtralPipeline.Configuration.default
        config.maxTokens = 256
        config.temperature = 0.0
        config.topP = 0.95
        config.repetitionPenalty = 1.15

        let pipeline = VoxtralPipeline(
            model: model.voxtralPipelineModel,
            backend: .hybrid,
            configuration: config
        )

        try await pipeline.loadModel()
        self.pipeline = pipeline
        self.loadedModel = model
    }

    func transcribe(audioURL: URL, mode: MLXTranscriptionMode) async throws -> String {
        guard let pipeline else {
            throw MLXError.pipelineUnavailable
        }

        switch mode {
        case .verbatim:
            return try await pipeline.transcribe(audio: audioURL, language: "en")
        case let .smart(prompt):
            return try await pipeline.chat(audio: audioURL, prompt: prompt, language: "en")
        }
    }

    func unloadModel() {
        pipeline?.unload()
        pipeline = nil
        loadedModel = nil
    }
}

private enum MLXError: LocalizedError {
    case pipelineUnavailable

    var errorDescription: String? {
        switch self {
        case .pipelineUnavailable:
            return "Transcription pipeline is not available."
        }
    }
}

private extension MLXModelInfo {
    var voxtralModelInfo: VoxtralModelInfo {
        if let model = ModelRegistry.model(withId: id) {
            return model
        }

        return VoxtralModelInfo(
            id: id,
            repoId: repoId,
            name: name,
            description: summary,
            size: size,
            quantization: quantization,
            parameters: parameters,
            recommended: recommended
        )
    }
}

private extension MLXPipelineModel {
    var voxtralPipelineModel: VoxtralPipeline.Model {
        switch self {
        case .mini3b:
            return .mini3b
        case .mini3b8bit:
            return .mini3b
        case .mini3b4bit:
            return .mini3b
        }
    }
}
