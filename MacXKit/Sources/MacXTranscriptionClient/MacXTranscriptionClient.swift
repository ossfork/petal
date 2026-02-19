import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import MacXShared
import VoxtralCore

public enum MacXTranscriptionClientError: LocalizedError, Sendable {
    case pipelineUnavailable

    public var errorDescription: String? {
        switch self {
        case .pipelineUnavailable:
            return "Transcription pipeline is not available."
        }
    }
}

@DependencyClient
public struct MacXTranscriptionClient: Sendable {
    public var prepareModelIfNeeded: @Sendable (MacXModelOption) async throws -> Void
    public var transcribe: @Sendable (URL, MacXModelOption, MacXTranscriptionMode, String?) async throws -> String
    public var unloadModel: @Sendable () async -> Void = {}
    public var audioDurationSeconds: @Sendable (URL) -> Double = { _ in 0 }
}

extension MacXTranscriptionClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = LiveTranscriptionRuntime()
        return Self(
            prepareModelIfNeeded: { option in
                try await runtime.prepareModelIfNeeded(option: option)
            },
            transcribe: { audioURL, option, mode, prompt in
                try await runtime.transcribe(audioURL: audioURL, option: option, mode: mode, prompt: prompt)
            },
            unloadModel: {
                await runtime.unloadModel()
            },
            audioDurationSeconds: { url in
                audioFileDurationSeconds(url)
            }
        )
    }
}

extension MacXTranscriptionClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            prepareModelIfNeeded: { _ in },
            transcribe: { _, _, _, _ in "Test transcription" },
            unloadModel: {},
            audioDurationSeconds: { _ in 1.0 }
        )
    }
}

public extension DependencyValues {
    var macXTranscriptionClient: MacXTranscriptionClient {
        get { self[MacXTranscriptionClient.self] }
        set { self[MacXTranscriptionClient.self] = newValue }
    }
}

private actor LiveTranscriptionRuntime {
    private var pipeline: VoxtralPipeline?
    private var loadedModel: MacXModelOption?

    func prepareModelIfNeeded(option: MacXModelOption) async throws {
        if loadedModel == option, pipeline != nil {
            return
        }

        unloadModel()

        var config = VoxtralPipeline.Configuration.default
        config.temperature = 0.0
        config.topP = 0.95
        config.repetitionPenalty = 1.15

        let pipeline = VoxtralPipeline(
            model: option.pipelineModel,
            backend: .hybrid,
            configuration: config
        )

        try await pipeline.loadModel()

        self.pipeline = pipeline
        self.loadedModel = option
    }

    func transcribe(
        audioURL: URL,
        option: MacXModelOption,
        mode: MacXTranscriptionMode,
        prompt: String?
    ) async throws -> String {
        try await prepareModelIfNeeded(option: option)

        guard let pipeline else {
            throw MacXTranscriptionClientError.pipelineUnavailable
        }

        switch mode {
        case .verbatim:
            return try await pipeline.transcribe(audio: audioURL, language: "en")
        case .smart:
            let instruction = prompt ?? "Clean up filler words and repeated phrases. Return a polished version of what was said."
            return try await pipeline.chat(audio: audioURL, prompt: instruction, language: "en")
        }
    }

    func unloadModel() {
        pipeline?.unload()
        pipeline = nil
        loadedModel = nil
    }
}

private func audioFileDurationSeconds(_ url: URL) -> Double {
    guard let file = try? AVAudioFile(forReading: url) else { return 0 }
    let sampleRate = file.fileFormat.sampleRate
    guard sampleRate > 0 else { return 0 }
    return Double(file.length) / sampleRate
}

private extension MacXModelOption {
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
}
