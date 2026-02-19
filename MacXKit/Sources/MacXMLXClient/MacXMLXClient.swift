import Dependencies
import DependenciesMacros
import Foundation
import VoxtralCore

public struct MacXMLXModelInfo: Sendable, Equatable {
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

public enum MacXMLXPipelineModel: String, Sendable {
    case mini3b
    case mini3b8bit
    case mini3b4bit
}

public enum MacXMLXTranscriptionMode: Sendable {
    case verbatim
    case smart(prompt: String)
}

@DependencyClient
public struct MacXMLXClient: Sendable {
    public var isModelDownloaded: @Sendable (MacXMLXModelInfo) -> Bool = { _ in false }
    public var downloadModel: @Sendable (MacXMLXModelInfo, @escaping @Sendable (Double, String) -> Void) async throws -> Void
    public var prepareModelIfNeeded: @Sendable (MacXMLXPipelineModel) async throws -> Void
    public var transcribe: @Sendable (URL, MacXMLXTranscriptionMode) async throws -> String
    public var unloadModel: @Sendable () async -> Void = {}
}

extension MacXMLXClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = LiveMacXMLXRuntime()
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

extension MacXMLXClient: TestDependencyKey {
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
    var macXMLXClient: MacXMLXClient {
        get { self[MacXMLXClient.self] }
        set { self[MacXMLXClient.self] = newValue }
    }
}

private actor LiveMacXMLXRuntime {
    private var pipeline: VoxtralPipeline?
    private var loadedModel: MacXMLXPipelineModel?

    func prepareModelIfNeeded(model: MacXMLXPipelineModel) async throws {
        if loadedModel == model, pipeline != nil {
            return
        }

        unloadModel()

        var config = VoxtralPipeline.Configuration.default
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

    func transcribe(audioURL: URL, mode: MacXMLXTranscriptionMode) async throws -> String {
        guard let pipeline else {
            throw MacXMLXError.pipelineUnavailable
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

private enum MacXMLXError: LocalizedError {
    case pipelineUnavailable

    var errorDescription: String? {
        switch self {
        case .pipelineUnavailable:
            return "Transcription pipeline is not available."
        }
    }
}

private extension MacXMLXModelInfo {
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

private extension MacXMLXPipelineModel {
    var voxtralPipelineModel: VoxtralPipeline.Model {
        switch self {
        case .mini3b:
            return .mini3b
        case .mini3b8bit:
            return .mini3b8bit
        case .mini3b4bit:
            return .mini3b4bit
        }
    }
}
