import Dependencies
import DependenciesMacros
import Foundation
import HuggingFace
import MLXAudioCore
import MLXAudioSTT
import VoxtralCore
import WhisperKit

/// Root directory for all Gloam data: ~/Documents/Gloam/
private let gloamDirectory: URL = {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Gloam")
}()

/// HubCache rooted at ~/Documents/Gloam/models/ so mlx-audio-swift stores models there.
private let gloamHubCache = HubCache(cacheDirectory: gloamDirectory.appendingPathComponent("models"))

public enum MLXModelBackend: String, Sendable, Equatable {
    case voxtral
    case mlxAudioSTT
    case whisperKit
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
    case whisperLargeV3Turbo
    case whisperTiny
}

public enum MLXTranscriptionMode: Sendable {
    case verbatim
    case smart(prompt: String)
}

public enum MLXDownloadError: LocalizedError, Sendable, Equatable {
    case paused
    case cancelled
    case aria2BinaryMissing
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .paused:
            return "Download paused"
        case .cancelled:
            return "Download cancelled"
        case .aria2BinaryMissing:
            return "aria2c binary is missing from the app bundle or system PATH."
        case let .failed(message):
            return message
        }
    }
}

@DependencyClient
public struct MLXClient: Sendable {
    public var isModelDownloaded: @Sendable (MLXModelInfo) -> Bool = { _ in false }
    public var downloadModel: @Sendable (MLXModelInfo, @escaping @Sendable (Double, String) -> Void) async throws -> Void
    public var pauseDownload: @Sendable () -> Void = {}
    public var cancelDownload: @Sendable () -> Void = {}
    public var modelDirectoryURL: @Sendable (MLXModelInfo) -> URL? = { _ in nil }
    public var deleteModel: @Sendable (MLXModelInfo) async throws -> Void
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
                case .mlxAudioSTT:
                    return MLXAudioCache.isModelDownloaded(repoId: info.repoId)
                case .whisperKit:
                    return WhisperKitCache.isModelDownloaded(variant: info.id)
                }
            },
            downloadModel: { info, progress in
                do {
                    switch info.backend {
                    case .voxtral:
                        _ = try await ModelDownloader.download(info.voxtralModelInfo, progress: progress)
                    case .mlxAudioSTT:
                        try await MLXAudioCache.downloadSnapshotIfNeeded(repoId: info.repoId, progress: progress)
                    case .whisperKit:
                        try await WhisperKitCache.downloadIfNeeded(variant: info.id, progress: progress)
                    }
                } catch {
                    throw normalizeDownloadError(error)
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
                case .mlxAudioSTT:
                    return ModelDownloader.findModelPath(for: info.voxtralModelInfo)
                case .whisperKit:
                    return WhisperKitCache.modelDirectoryURL(variant: info.id)
                }
            },
            deleteModel: { info in
                switch info.backend {
                case .voxtral:
                    if let path = ModelDownloader.findModelPath(for: info.voxtralModelInfo) {
                        try FileManager.default.removeItem(at: path)
                    }
                case .mlxAudioSTT:
                    try MLXAudioCache.deleteModel(repoId: info.repoId)
                case .whisperKit:
                    try WhisperKitCache.deleteModel(variant: info.id)
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
            pauseDownload: {},
            cancelDownload: {},
            modelDirectoryURL: { _ in nil },
            deleteModel: { _ in },
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
    private var whisperKitInstance: WhisperKit?

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
            self.qwen3ASRModel = try await Qwen3ASRModel.fromPretrained(repoID, cache: gloamHubCache)

        case .whisperLargeV3Turbo, .whisperTiny:
            guard let variant = model.whisperKitVariant else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            self.whisperKitInstance = try await WhisperKit(model: variant, downloadBase: gloamDirectory)
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

        case .whisperLargeV3Turbo, .whisperTiny:
            guard let whisperKitInstance else {
                throw MLXError.pipelineUnavailable
            }
            nonisolated(unsafe) let instance = whisperKitInstance
            let audioPath = audioURL.path
            let results = try await instance.transcribe(audioPath: audioPath)
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw MLXError.pipelineUnavailable
            }
            return text
        }
    }

    func unloadModel() {
        voxtralPipeline?.unload()
        voxtralPipeline = nil
        qwen3ASRModel = nil
        whisperKitInstance = nil
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

}

private enum MLXError: LocalizedError {
    case invalidModelIdentifier(String)
    case pipelineUnavailable

    var errorDescription: String? {
        switch self {
        case let .invalidModelIdentifier(identifier):
            return "Invalid model identifier: \(identifier)"
        case .pipelineUnavailable:
            return "Transcription pipeline is not available."
        }
    }
}

private func normalizeDownloadError(_ error: any Error) -> MLXDownloadError {
    if let downloadError = error as? MLXDownloadError {
        return downloadError
    }

    if let downloaderError = error as? ModelDownloaderError {
        switch downloaderError {
        case .downloadPaused:
            return .paused
        case .downloadCancelled:
            return .cancelled
        case .aria2BinaryMissing:
            return .aria2BinaryMissing
        case let .downloadFailed(message):
            return .failed(message)
        case .modelNotFound:
            return .failed(downloaderError.localizedDescription)
        }
    }

    return .failed(error.localizedDescription)
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

    static func deleteModel(repoId: String) throws {
        guard let repoID = Repo.ID(rawValue: repoId) else { return }
        let directory = modelDirectory(for: repoID)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static func modelDirectory(for repoID: Repo.ID) -> URL {
        let modelSubdirectory = repoID.description.replacingOccurrences(of: "/", with: "_")
        return gloamHubCache.cacheDirectory
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
        case .mini3b, .whisperLargeV3Turbo, .whisperTiny:
            return nil
        case .qwen3ASR06B4bit:
            return "mlx-community/Qwen3-ASR-0.6B-4bit"
        }
    }

    var whisperKitVariant: String? {
        switch self {
        case .whisperLargeV3Turbo:
            return "openai_whisper-large-v3_turbo"
        case .whisperTiny:
            return "openai_whisper-tiny"
        case .mini3b, .qwen3ASR06B4bit:
            return nil
        }
    }
}

private enum WhisperKitCache {
    static func isModelDownloaded(variant: String) -> Bool {
        guard let url = modelDirectoryURL(variant: variant) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func downloadIfNeeded(
        variant: String,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        progress(0, "Downloading WhisperKit model...")
        // WhisperKit handles download internally during init.
        // We trigger it here so the download client can report progress.
        _ = try await WhisperKit(model: whisperKitModelName(for: variant), downloadBase: gloamDirectory)
        progress(1, "Download complete")
    }

    static func deleteModel(variant: String) throws {
        guard let url = modelDirectoryURL(variant: variant) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func modelDirectoryURL(variant: String) -> URL? {
        let baseDir = gloamDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")

        let modelName = whisperKitModelName(for: variant)
        let modelDir = baseDir.appendingPathComponent(modelName)
        guard FileManager.default.fileExists(atPath: modelDir.path) else { return nil }
        return modelDir
    }

    private static func whisperKitModelName(for variant: String) -> String {
        switch variant {
        case "whisper-large-v3-turbo":
            return "openai_whisper-large-v3_turbo"
        case "whisper-tiny":
            return "openai_whisper-tiny"
        default:
            return variant
        }
    }
}
