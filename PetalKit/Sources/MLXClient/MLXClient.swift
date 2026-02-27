import AVFoundation
import Dependencies
import DependenciesMacros
import FluidAudio
import Foundation
import VoxtralCore
import WhisperKit

/// Root directory for all Petal data: ~/Documents/petal/
private let petalDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    .appendingPathComponent("petal")

public enum MLXModelBackend: String, Sendable, Equatable {
    case voxtral
    case fluidAudio
    case whisperKit
}

public struct MLXModelInfo: Sendable, Equatable {
    public var id: String
    public var repoId: String
    public var name: String
    public var summary: String
    public var size: String?
    public var quantization: String
    public var parameters: String
    public var backend: MLXModelBackend
    public var recommended: Bool

    public init(
        id: String,
        repoId: String,
        name: String,
        summary: String,
        size: String? = nil,
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
    case mini3b8bit
    case qwen3ASR06B4bit
    case parakeetTDT06BV3
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
                case .fluidAudio:
                    return FluidAudioCache.isModelDownloaded(info: info)
                case .whisperKit:
                    return WhisperKitCache.isModelDownloaded(variant: info.id)
                }
            },
            downloadModel: { info, progress in
                do {
                    switch info.backend {
                    case .voxtral:
                        _ = try await ModelDownloader.download(info.voxtralModelInfo, progress: progress)
                    case .fluidAudio:
                        try await FluidAudioCache.downloadIfNeeded(info: info, progress: progress)
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
                case .fluidAudio:
                    return FluidAudioCache.modelDirectoryURL(info: info)
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
                case .fluidAudio:
                    try FluidAudioCache.deleteModel(info: info)
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
    private let audioConverter = AudioConverter()

    private var loadedModel: MLXPipelineModel?
    private var voxtralPipeline: VoxtralPipeline?
    private var qwen3AsrManager: Qwen3AsrManager?
    private var parakeetAsrManager: AsrManager?
    private var whisperKitInstance: WhisperKit?

    func prepareModelIfNeeded(model: MLXPipelineModel) async throws {
        if loadedModel == model {
            return
        }

        unloadModel()

        switch model {
        case .mini3b, .mini3b8bit:
            var config = VoxtralPipeline.Configuration.default
            config.maxTokens = 256
            config.temperature = 0.0
            config.topP = 0.95
            config.repetitionPenalty = 1.15

            let pipeline = VoxtralPipeline(
                model: model.voxtralModel,
                backend: .hybrid,
                configuration: config
            )

            try await pipeline.loadModel()
            voxtralPipeline = pipeline

        case .qwen3ASR06B4bit:
            guard let fluidAudioModel = model.fluidAudioModel else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            let modelDirectory = try await FluidAudioCache.downloadIfNeeded(model: fluidAudioModel)
            let manager = Qwen3AsrManager()
            try await manager.loadModels(from: modelDirectory)
            qwen3AsrManager = manager

        case .parakeetTDT06BV3:
            guard let fluidAudioModel = model.fluidAudioModel else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            let modelDirectory = try await FluidAudioCache.downloadIfNeeded(model: fluidAudioModel)
            let asrModels = try await AsrModels.load(from: modelDirectory, version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: asrModels)
            parakeetAsrManager = manager

        case .whisperLargeV3Turbo, .whisperTiny:
            guard let variant = model.whisperKitVariant else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            whisperKitInstance = try await WhisperKit(model: variant, downloadBase: petalDirectory)
        }

        loadedModel = model
    }

    func transcribe(audioURL: URL, mode: MLXTranscriptionMode) async throws -> String {
        guard let loadedModel else {
            throw MLXError.pipelineUnavailable
        }

        switch loadedModel {
        case .mini3b, .mini3b8bit:
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
            guard let qwen3AsrManager else {
                throw MLXError.pipelineUnavailable
            }

            let audioSamples = try audioConverter.resampleAudioFile(audioURL)
            let text = try await qwen3AsrManager.transcribe(audioSamples: audioSamples)
            let normalizedText = normalizeQwenTranscript(text)
            guard !normalizedText.isEmpty else {
                throw MLXError.pipelineUnavailable
            }

            switch mode {
            case .verbatim:
                return normalizedText
            case .smart:
                return normalizedText
            }

        case .parakeetTDT06BV3:
            guard let parakeetAsrManager else {
                throw MLXError.pipelineUnavailable
            }

            nonisolated(unsafe) let manager = parakeetAsrManager
            let result = try await manager.transcribe(audioURL, source: .system)
            let text = normalizeParakeetTranscript(result.text)
            guard !text.isEmpty else {
                throw MLXError.pipelineUnavailable
            }

            switch mode {
            case .verbatim:
                return text
            case .smart:
                return text
            }

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
        qwen3AsrManager = nil
        parakeetAsrManager = nil
        whisperKitInstance = nil
        loadedModel = nil
    }

    private func normalizeQwenTranscript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeParakeetTranscript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum FluidAudioModel: Sendable, Equatable {
    case qwen3Asr
    case parakeetTdt06BV3

    init?(info: MLXModelInfo) {
        let normalizedID = info.id.lowercased()
        let normalizedRepo = info.repoId.lowercased()

        switch normalizedID {
        case MLXPipelineModel.qwen3ASR06B4bit.rawValue:
            self = .qwen3Asr
        case MLXPipelineModel.parakeetTDT06BV3.rawValue:
            self = .parakeetTdt06BV3
        default:
            switch normalizedRepo {
            case "fluidinference/qwen3-asr-0.6b-coreml/f32",
                 "fluidinference/qwen3-asr-0.6b-coreml/int8",
                 "mlx-community/qwen3-asr-0.6b-4bit":
                self = .qwen3Asr
            case "fluidinference/parakeet-tdt-0.6b-v3-coreml",
                 "mlx-community/parakeet-tdt-0.6b-v3":
                self = .parakeetTdt06BV3
            default:
                return nil
            }
        }
    }

    var directoryURL: URL {
        switch self {
        case .qwen3Asr:
            return Qwen3AsrModels.defaultCacheDirectory()
        case .parakeetTdt06BV3:
            return AsrModels.defaultCacheDirectory(for: .v3)
        }
    }

    var candidateDirectoryURLs: [URL] {
        switch self {
        case .qwen3Asr:
            let defaultDirectory = Qwen3AsrModels.defaultCacheDirectory()
            let repoDirectory = defaultDirectory.deletingLastPathComponent()
            let modelsRoot = repoDirectory.deletingLastPathComponent()

            return [
                defaultDirectory,
                repoDirectory,
                repoDirectory.appendingPathComponent("qwen3-asr-0.6b-coreml-f32", isDirectory: true),
                modelsRoot.appendingPathComponent("qwen3-asr-0.6b-coreml-f32", isDirectory: true),
            ]
        case .parakeetTdt06BV3:
            return [AsrModels.defaultCacheDirectory(for: .v3)]
        }
    }

    var displayName: String {
        switch self {
        case .qwen3Asr:
            return "Qwen3 ASR"
        case .parakeetTdt06BV3:
            return "Parakeet TDT"
        }
    }
}

private enum FluidAudioCache {
    static func isModelDownloaded(info: MLXModelInfo) -> Bool {
        guard let model = FluidAudioModel(info: info) else { return false }
        return isModelDownloaded(model: model)
    }

    static func downloadIfNeeded(
        info: MLXModelInfo,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        guard let model = FluidAudioModel(info: info) else {
            throw MLXError.invalidModelIdentifier(info.id)
        }
        _ = try await downloadIfNeeded(model: model, progress: progress)
    }

    @discardableResult
    static func downloadIfNeeded(model: FluidAudioModel) async throws -> URL {
        try await downloadIfNeeded(model: model, progress: nil)
    }

    static func modelDirectoryURL(info: MLXModelInfo) -> URL? {
        guard let model = FluidAudioModel(info: info) else { return nil }
        return resolvedDirectoryURL(for: model)
    }

    static func deleteModel(info: MLXModelInfo) throws {
        guard let model = FluidAudioModel(info: info) else {
            throw MLXError.invalidModelIdentifier(info.id)
        }
        for directory in model.candidateDirectoryURLs {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    private static func isModelDownloaded(model: FluidAudioModel) -> Bool {
        resolvedDirectoryURL(for: model) != nil
    }

    private static func resolvedDirectoryURL(for model: FluidAudioModel) -> URL? {
        switch model {
        case .qwen3Asr:
            for candidate in model.candidateDirectoryURLs {
                if Qwen3AsrModels.modelsExist(at: candidate) {
                    return candidate
                }
            }
            return nil
        case .parakeetTdt06BV3:
            let defaultDirectory = model.directoryURL
            return AsrModels.modelsExist(at: defaultDirectory, version: .v3) ? defaultDirectory : nil
        }
    }

    @discardableResult
    private static func downloadIfNeeded(
        model: FluidAudioModel,
        progress: (@Sendable (Double, String) -> Void)?
    ) async throws -> URL {
        if let existingDirectory = resolvedDirectoryURL(for: model) {
            progress?(1, "Model already downloaded")
            return existingDirectory
        }

        progress?(0, "Downloading \(model.displayName) model...")

        switch model {
        case .qwen3Asr:
            do {
                _ = try await Qwen3AsrModels.download()
            } catch {
                progress?(0.05, "Retrying Qwen3 ASR download from Hugging Face...")
                try await Qwen3AsrFallbackDownloader.download(to: Qwen3AsrModels.defaultCacheDirectory())
            }
        case .parakeetTdt06BV3:
            _ = try await AsrModels.download(version: .v3)
        }

        if model == .qwen3Asr, resolvedDirectoryURL(for: model) == nil {
            progress?(0.1, "Applying Qwen3 ASR download compatibility fix...")
            try await Qwen3AsrFallbackDownloader.download(to: Qwen3AsrModels.defaultCacheDirectory())
        }

        guard let resolvedDirectory = resolvedDirectoryURL(for: model) else {
            throw MLXDownloadError.failed("Downloaded model files were not detected in cache.")
        }

        progress?(1, "Download complete")
        return resolvedDirectory
    }
}

private enum Qwen3AsrFallbackDownloader {
    private static let repoID = "FluidInference/qwen3-asr-0.6b-coreml"
    private static let variantPath = "f32"
    private static let requiredLocalFiles = [
        "qwen3_asr_audio_encoder.mlmodelc",
        "qwen3_asr_decoder_stateful.mlmodelc",
        "qwen3_asr_embeddings.bin",
        "vocab.json",
    ]
    private static let requiredRemoteFilePaths = Set([
        "f32/qwen3_asr_embeddings.bin",
        "f32/vocab.json",
    ])
    private static let requiredRemoteDirectoryPrefixes = [
        "f32/qwen3_asr_audio_encoder.mlmodelc/",
        "f32/qwen3_asr_decoder_stateful.mlmodelc/",
    ]

    private struct HuggingFaceTreeItem: Decodable {
        let type: String
        let path: String
    }

    static func download(to directory: URL) async throws {
        if Qwen3AsrModels.modelsExist(at: directory) {
            return
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filePaths = try await listRequiredRemoteFiles()
        for remotePath in filePaths {
            let localRelativePath = String(remotePath.dropFirst("\(variantPath)/".count))
            let destinationURL = directory.appendingPathComponent(localRelativePath)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                continue
            }

            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let sourceURL = try resolveURL(for: remotePath)
            let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                throw MLXDownloadError.failed("Failed downloading Qwen3 ASR file: \(remotePath)")
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }

        guard Qwen3AsrModels.modelsExist(at: directory) else {
            let missing = requiredLocalFiles.filter { file in
                !FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path)
            }
            throw MLXDownloadError.failed(
                "Qwen3 ASR download incomplete. Missing files: \(missing.joined(separator: ", "))"
            )
        }
    }

    private static func listRequiredRemoteFiles() async throws -> [String] {
        let apiURL = URL(
            string: "https://huggingface.co/api/models/\(repoID)/tree/main/\(variantPath)?recursive=1"
        )!
        let (data, response) = try await URLSession.shared.data(from: apiURL)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw MLXDownloadError.failed("Unable to list files for \(repoID)/\(variantPath).")
        }

        let items = try JSONDecoder().decode([HuggingFaceTreeItem].self, from: data)
        let files = items
            .filter { $0.type == "file" }
            .map(\.path)
            .filter { path in
                requiredRemoteFilePaths.contains(path)
                    || requiredRemoteDirectoryPrefixes.contains(where: { path.hasPrefix($0) })
            }
            .sorted()

        guard !files.isEmpty else {
            throw MLXDownloadError.failed(
                "No files found for \(repoID)/\(variantPath). Repository layout may have changed."
            )
        }
        return files
    }

    private static func resolveURL(for remotePath: String) throws -> URL {
        let encodedPath = remotePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remotePath
        guard let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encodedPath)") else {
            throw MLXDownloadError.failed("Invalid Qwen3 ASR download URL for path: \(remotePath)")
        }
        return url
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
            size: size ?? "",
            quantization: quantization,
            parameters: parameters,
            recommended: recommended
        )
    }
}

private extension MLXPipelineModel {
    var fluidAudioModel: FluidAudioModel? {
        switch self {
        case .qwen3ASR06B4bit:
            return .qwen3Asr
        case .parakeetTDT06BV3:
            return .parakeetTdt06BV3
        case .mini3b, .mini3b8bit, .whisperLargeV3Turbo, .whisperTiny:
            return nil
        }
    }

    var whisperKitVariant: String? {
        switch self {
        case .whisperLargeV3Turbo:
            return "openai_whisper-large-v3_turbo"
        case .whisperTiny:
            return "openai_whisper-tiny"
        case .mini3b, .mini3b8bit, .qwen3ASR06B4bit, .parakeetTDT06BV3:
            return nil
        }
    }

    var voxtralModel: VoxtralPipeline.Model {
        switch self {
        case .mini3b:
            return .mini3b
        case .mini3b8bit:
            return .mini3b8bit
        case .qwen3ASR06B4bit, .parakeetTDT06BV3, .whisperLargeV3Turbo, .whisperTiny:
            return .mini3b
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
        if isModelDownloaded(variant: variant) {
            progress(1, "Model already downloaded")
            return
        }

        progress(0, "Downloading WhisperKit model...")
        let modelName = whisperKitModelName(for: variant)

        _ = try await WhisperKit.download(
            variant: modelName,
            downloadBase: petalDirectory
        ) { downloadProgress in
            let fraction = downloadProgress.fractionCompleted
            let percent = Int((fraction * 100).rounded())
            progress(fraction, "Downloading WhisperKit model... \(percent)%")
        }
        progress(1, "Download complete")
    }

    static func deleteModel(variant: String) throws {
        guard let url = modelDirectoryURL(variant: variant) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func modelDirectoryURL(variant: String) -> URL? {
        let baseDir = petalDirectory
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
