import Dependencies
import DependenciesMacros
import Foundation
import HuggingFace
import MLXAudioCore
import MLXAudioSTT
import VoxtralCore

public enum MLXModelBackend: String, Sendable, Equatable {
    case voxtral
    case mlxAudioSTT
    case mlxWhisper
}

public struct MLXModelInfo: Sendable, Equatable {
    public var id: String
    public var repoId: String
    public var name: String
    public var summary: String
    public var size: String
    public var quantization: String
    public var parameters: String
    public var backend: MLXModelBackend
    public var recommended: Bool

    public init(
        id: String,
        repoId: String,
        name: String,
        summary: String,
        size: String,
        quantization: String,
        parameters: String,
        backend: MLXModelBackend,
        recommended: Bool
    ) {
        self.id = id
        self.repoId = repoId
        self.name = name
        self.summary = summary
        self.size = size
        self.quantization = quantization
        self.parameters = parameters
        self.backend = backend
        self.recommended = recommended
    }
}

public enum MLXPipelineModel: String, Sendable {
    case mini3b
    case qwen3ASR06B4bit
    case whisperLargeV3TurboASRFP16
    case whisperTinyMLX
}

public enum MLXTranscriptionMode: Sendable {
    case verbatim
    case smart(prompt: String)
}

@DependencyClient
public struct MLXClient: Sendable {
    public var isModelDownloaded: @Sendable (MLXModelInfo) -> Bool = { _ in false }
    public var downloadModel: @Sendable (MLXModelInfo, @escaping @Sendable (Double, String) -> Void) async throws -> Void
    public var pauseDownload: @Sendable () -> Void = {}
    public var cancelDownload: @Sendable () -> Void = {}
    public var modelDirectoryURL: @Sendable (MLXModelInfo) -> URL? = { _ in nil }
    public var prepareModelIfNeeded: @Sendable (MLXPipelineModel) async throws -> Void
    public var transcribe: @Sendable (URL, MLXTranscriptionMode) async throws -> String
    public var unloadModel: @Sendable () async -> Void = {}
}

extension MLXClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = LiveMLXRuntime()
        return Self(
            isModelDownloaded: { info in
                switch info.backend {
                case .voxtral:
                    return ModelDownloader.findModelPath(for: info.voxtralModelInfo) != nil
                case .mlxAudioSTT, .mlxWhisper:
                    return MLXAudioCache.isModelDownloaded(repoId: info.repoId)
                }
            },
            downloadModel: { info, progress in
                switch info.backend {
                case .voxtral:
                    _ = try await ModelDownloader.download(info.voxtralModelInfo, progress: progress)
                case .mlxAudioSTT, .mlxWhisper:
                    try await MLXAudioCache.downloadSnapshotIfNeeded(repoId: info.repoId, progress: progress)
                }
            },
            pauseDownload: {
                ModelDownloader.pauseDownload()
            },
            cancelDownload: {
                ModelDownloader.cancelDownload()
            },
            modelDirectoryURL: { info in
                switch info.backend {
                case .voxtral:
                    return ModelDownloader.findModelPath(for: info.voxtralModelInfo)
                case .mlxAudioSTT, .mlxWhisper:
                    return ModelDownloader.findModelPath(for: info.voxtralModelInfo)
                }
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
    private var loadedModel: MLXPipelineModel?
    private var voxtralPipeline: VoxtralPipeline?
    private var qwen3ASRModel: Qwen3ASRModel?

    func prepareModelIfNeeded(model: MLXPipelineModel) async throws {
        if loadedModel == model {
            return
        }

        unloadModel()

        switch model {
        case .mini3b:
            var config = VoxtralPipeline.Configuration.default
            config.maxTokens = 256
            config.temperature = 0.0
            config.topP = 0.95
            config.repetitionPenalty = 1.15

            let pipeline = VoxtralPipeline(
                model: .mini3b,
                backend: .hybrid,
                configuration: config
            )

            try await pipeline.loadModel()
            self.voxtralPipeline = pipeline

        case .qwen3ASR06B4bit:
            guard let repoID = model.qwenRepoID else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            self.qwen3ASRModel = try await Qwen3ASRModel.fromPretrained(repoID)
        case .whisperLargeV3TurboASRFP16, .whisperTinyMLX:
            break
        }

        self.loadedModel = model
    }

    func transcribe(audioURL: URL, mode: MLXTranscriptionMode) async throws -> String {
        guard let loadedModel else {
            throw MLXError.pipelineUnavailable
        }

        switch loadedModel {
        case .mini3b:
            guard let voxtralPipeline else {
                throw MLXError.pipelineUnavailable
            }

            switch mode {
            case .verbatim:
                return try await voxtralPipeline.transcribe(audio: audioURL, language: "en")
            case let .smart(prompt):
                return try await voxtralPipeline.chat(audio: audioURL, prompt: prompt, language: "en")
            }

        case .qwen3ASR06B4bit:
            guard let qwen3ASRModel else {
                throw MLXError.pipelineUnavailable
            }
            return try transcribeWithQwen(audioURL: audioURL, mode: mode, model: qwen3ASRModel)
        case .whisperLargeV3TurboASRFP16, .whisperTinyMLX:
            guard let repoID = loadedModel.whisperRepoID else {
                throw MLXError.invalidModelIdentifier(loadedModel.rawValue)
            }
            return try await transcribeWithWhisper(audioURL: audioURL, mode: mode, repoID: repoID)
        }
    }

    func unloadModel() {
        voxtralPipeline?.unload()
        voxtralPipeline = nil
        qwen3ASRModel = nil
        loadedModel = nil
    }

    // Qwen3 ASR currently supports direct ASR generation only, so smart mode falls back to verbatim output.
    private func transcribeWithQwen(
        audioURL: URL,
        mode: MLXTranscriptionMode,
        model: Qwen3ASRModel
    ) throws -> String {
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: model.sampleRate)
        let output = model.generate(
            audio: audio,
            generationParameters: STTGenerateParameters(language: "English")
        )
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .verbatim:
            return text
        case .smart:
            return text
        }
    }

    private func transcribeWithWhisper(
        audioURL: URL,
        mode: MLXTranscriptionMode,
        repoID: String
    ) async throws -> String {
        let text = try await runWhisperTranscription(audioURL: audioURL, repoID: repoID)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .verbatim:
            return text
        case .smart:
            return text
        }
    }
}

private enum MLXError: LocalizedError {
    case invalidModelIdentifier(String)
    case pipelineUnavailable
    case whisperRuntimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .invalidModelIdentifier(identifier):
            return "Invalid model identifier: \(identifier)"
        case .pipelineUnavailable:
            return "Transcription pipeline is not available."
        case let .whisperRuntimeUnavailable(message):
            return "Whisper runtime is unavailable: \(message)"
        }
    }
}

private enum MLXAudioCache {
    static func isModelDownloaded(repoId: String) -> Bool {
        guard let repoID = Repo.ID(rawValue: repoId) else { return false }
        let modelDirectory = modelDirectory(for: repoID)

        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            return false
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return false
        }

        return files.contains { file in
            guard file.pathExtension == "safetensors" else { return false }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size > 0
        }
    }

    static func downloadSnapshotIfNeeded(
        repoId: String,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        guard let repoID = Repo.ID(rawValue: repoId) else {
            throw MLXError.invalidModelIdentifier(repoId)
        }

        if isModelDownloaded(repoId: repoId) {
            progress(1, "Model already downloaded")
            return
        }

        // Reuse the existing aria2c downloader path for consistency with Voxtral downloads.
        let downloadInfo = VoxtralModelInfo(
            id: repoId.replacingOccurrences(of: "/", with: "--"),
            repoId: repoId,
            name: repoId,
            description: "MLX Audio model",
            size: "Unknown",
            quantization: "Unknown",
            parameters: "Unknown",
            recommended: false
        )

        let downloadedPath = try await ModelDownloader.download(downloadInfo, progress: progress)
        try linkIntoMLXAudioCache(source: downloadedPath, repoID: repoID)
        progress(1, "Download complete")
    }

    private static func modelDirectory(for repoID: Repo.ID) -> URL {
        let modelSubdirectory = repoID.description.replacingOccurrences(of: "/", with: "_")
        return HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdirectory)
    }

    private static func linkIntoMLXAudioCache(source: URL, repoID: Repo.ID) throws {
        let destination = modelDirectory(for: repoID)
        let sourcePath = source.resolvingSymlinksInPath().path
        let destinationPath = destination.resolvingSymlinksInPath().path
        let fileManager = FileManager.default

        if sourcePath == destinationPath {
            return
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
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
    var qwenRepoID: String? {
        switch self {
        case .mini3b:
            return nil
        case .qwen3ASR06B4bit:
            return "mlx-community/Qwen3-ASR-0.6B-4bit"
        case .whisperLargeV3TurboASRFP16, .whisperTinyMLX:
            return nil
        }
    }

    var whisperRepoID: String? {
        switch self {
        case .mini3b, .qwen3ASR06B4bit:
            return nil
        case .whisperLargeV3TurboASRFP16:
            return "mlx-community/whisper-large-v3-turbo-asr-fp16"
        case .whisperTinyMLX:
            return "mlx-community/whisper-tiny-mlx"
        }
    }
}

private func runWhisperTranscription(audioURL: URL, repoID: String) async throws -> String {
    try await Task.detached(priority: .utility) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            "-c",
            """
            import json
            import sys

            audio_path = sys.argv[1]
            repo_id = sys.argv[2]

            try:
                import mlx_whisper
            except Exception:
                print(json.dumps({
                    "error": "Python module `mlx_whisper` is required for Whisper models. Install it with `pip3 install mlx-whisper`."
                }))
                raise SystemExit(2)

            result = mlx_whisper.transcribe(audio_path, path_or_hf_repo=repo_id, language="en")
            if isinstance(result, dict):
                text = result.get("text", "")
            else:
                text = str(result)
            print(json.dumps({"text": text}))
            """,
            audioURL.path,
            repoID,
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw MLXError.whisperRuntimeUnavailable(error.localizedDescription)
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(decoding: stdoutData, as: UTF8.self)
        let stderrText = String(decoding: stderrData, as: UTF8.self)

        let lines = stdoutText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let lastLine = lines.last,
           let data = lastLine.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            if process.terminationStatus == 0 {
                if let text = json["text"] as? String {
                    return text
                }
                throw MLXError.whisperRuntimeUnavailable("Whisper returned an unexpected payload.")
            }

            let message = (json["error"] as? String) ?? stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MLXError.whisperRuntimeUnavailable(message.isEmpty ? "Unknown Whisper runtime error." : message)
        }

        if process.terminationStatus == 0 {
            let fallback = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                return fallback
            }
        }

        let message = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        throw MLXError.whisperRuntimeUnavailable(message.isEmpty ? "Whisper transcription failed." : message)
    }.value
}
