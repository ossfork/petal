import Dependencies
import DependenciesMacros
import Foundation
import HuggingFace
import MLXAudioCore
import MLXAudioSTT
import VoxtralCore
import WhisperKit

/// Root directory for all Petal data: ~/Documents/petal/
private let petalDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    .appendingPathComponent("petal")

/// HubCache rooted at ~/Documents/petal/models/ so mlx-audio-swift stores models there.
private let petalHubCache = HubCache(cacheDirectory: petalDirectory.appendingPathComponent("models"))

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
    case parakeetCTC06B
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
    private static let qwenPrimaryParams = STTGenerateParameters(
        maxTokens: 2048,
        temperature: 0.0,
        language: "English",
        chunkDuration: 30.0,
        minChunkDuration: 1.0
    )
    private static let qwenFallbackParams = STTGenerateParameters(
        maxTokens: 1536,
        temperature: 0.0,
        language: "English",
        chunkDuration: 15.0,
        minChunkDuration: 1.0
    )

    private var loadedModel: MLXPipelineModel?
    private var voxtralPipeline: VoxtralPipeline?
    private var qwen3ASRModel: Qwen3ASRModel?
    private var parakeetModel: ParakeetModel?
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
            guard let repoID = model.qwenRepoID else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            qwen3ASRModel = try await Qwen3ASRModel.fromPretrained(repoID, cache: petalHubCache)

        case .parakeetTDT06BV3, .parakeetCTC06B:
            guard let repoID = model.parakeetRepoID else {
                throw MLXError.invalidModelIdentifier(model.rawValue)
            }
            parakeetModel = try await ParakeetModel.fromPretrained(repoID, cache: petalHubCache)

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
            guard let qwen3ASRModel else {
                throw MLXError.pipelineUnavailable
            }
            return try transcribeWithQwen(audioURL: audioURL, mode: mode, model: qwen3ASRModel)

        case .parakeetTDT06BV3, .parakeetCTC06B:
            guard let parakeetModel else {
                throw MLXError.pipelineUnavailable
            }
            return try transcribeWithParakeet(audioURL: audioURL, mode: mode, model: parakeetModel)

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
        parakeetModel = nil
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
        let primaryOutput = model.generate(
            audio: audio,
            generationParameters: Self.qwenPrimaryParams
        )
        let primaryText = normalizeQwenTranscript(primaryOutput.text)
        let text: String

        if QwenTranscriptGuard.isLikelyLooped(primaryText) {
            let fallbackOutput = model.generate(
                audio: audio,
                generationParameters: Self.qwenFallbackParams
            )
            let fallbackText = normalizeQwenTranscript(fallbackOutput.text)

            if fallbackText.isEmpty {
                text = primaryText
            } else if QwenTranscriptGuard.isLikelyLooped(fallbackText) {
                text = QwenTranscriptGuard.preferredTranscript(primary: primaryText, fallback: fallbackText)
            } else {
                text = fallbackText
            }
        } else {
            text = primaryText
        }

        switch mode {
        case .verbatim:
            return text
        case .smart:
            return text
        }
    }

    private func normalizeQwenTranscript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Parakeet currently supports direct ASR generation only, so smart mode falls back to verbatim output.
    private func transcribeWithParakeet(
        audioURL: URL,
        mode: MLXTranscriptionMode,
        model: ParakeetModel
    ) throws -> String {
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: model.preprocessConfig.sampleRate)
        let output = model.generate(audio: audio)
        let text = normalizeParakeetTranscript(output.text)
        guard !text.isEmpty else {
            throw MLXError.pipelineUnavailable
        }

        switch mode {
        case .verbatim:
            return text
        case .smart:
            return text
        }
    }

    private func normalizeParakeetTranscript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum QwenTranscriptGuard {
    static func isLikelyLooped(_ text: String) -> Bool {
        let words = words(in: text)
        guard words.count >= 16 else { return false }

        let metrics = LoopMetrics(words: words)
        let dominantShare = Double(metrics.maxFrequency) / Double(words.count)

        if metrics.longestRun >= 7 { return true }
        if dominantShare >= 0.5, metrics.uniqueRatio <= 0.3 { return true }
        if metrics.hasRepeatedNGram(n: 3, minRepeats: 5), metrics.uniqueRatio <= 0.45 { return true }
        return false
    }

    static func preferredTranscript(primary: String, fallback: String) -> String {
        let primaryMetrics = LoopMetrics(words: words(in: primary))
        let fallbackMetrics = LoopMetrics(words: words(in: fallback))
        let primaryScore = primaryMetrics.qualityScore
        let fallbackScore = fallbackMetrics.qualityScore

        if primaryScore == fallbackScore {
            return primary.count <= fallback.count ? primary : fallback
        }
        return primaryScore >= fallbackScore ? primary : fallback
    }

    private static func words(in text: String) -> [String] {
        text
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
    }

    private struct LoopMetrics {
        let words: [String]
        let uniqueRatio: Double
        let maxFrequency: Int
        let longestRun: Int

        init(words: [String]) {
            self.words = words
            if words.isEmpty {
                uniqueRatio = 0
                maxFrequency = 0
                longestRun = 0
                return
            }

            var counts: [String: Int] = [:]
            counts.reserveCapacity(words.count)

            var currentRun = 0
            var lastWord: String?
            var bestRun = 0

            for word in words {
                counts[word, default: 0] += 1

                if word == lastWord {
                    currentRun += 1
                } else {
                    currentRun = 1
                    lastWord = word
                }

                if currentRun > bestRun {
                    bestRun = currentRun
                }
            }

            uniqueRatio = Double(counts.count) / Double(words.count)
            maxFrequency = counts.values.max() ?? 0
            longestRun = bestRun
        }

        var qualityScore: Double {
            guard !words.isEmpty else { return -Double.greatestFiniteMagnitude }
            let runPenalty = Double(longestRun) / Double(words.count)
            let dominancePenalty = Double(maxFrequency) / Double(words.count)
            return uniqueRatio - runPenalty - dominancePenalty
        }

        func hasRepeatedNGram(n: Int, minRepeats: Int) -> Bool {
            guard n > 0, words.count >= n * minRepeats else { return false }

            var counts: [String: Int] = [:]
            counts.reserveCapacity(words.count / n)
            let limit = words.count - n

            for index in 0...limit {
                let key = words[index..<(index + n)].joined(separator: " ")
                counts[key, default: 0] += 1
                if counts[key, default: 0] >= minRepeats {
                    return true
                }
            }
            return false
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
        candidateModelDirectories(repoId: repoId).contains { hasDownloadedWeights(at: $0) }
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
            size: "",
            quantization: "",
            parameters: "",
            recommended: false
        )

        let downloadedPath = try await ModelDownloader.download(downloadInfo, progress: progress)
        try linkIntoMLXAudioCache(source: downloadedPath, repoID: repoID)

        guard isModelDownloaded(repoId: repoId) else {
            throw ModelDownloaderError.downloadFailed("Downloaded model files were not detected in cache.")
        }
        progress(1, "Download complete")
    }

    static func deleteModel(repoId: String) throws {
        let fileManager = FileManager.default
        var firstError: (any Error)?
        let paths = candidateModelDirectories(repoId: repoId).sorted { $0.path.count > $1.path.count }

        for path in paths where fileManager.fileExists(atPath: path.path) {
            do {
                try fileManager.removeItem(at: path)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private static func candidateModelDirectories(repoId: String) -> [URL] {
        var paths: [URL] = []
        var seen = Set<String>()

        func appendUnique(_ url: URL) {
            let normalizedPath = url.standardizedFileURL.path
            guard seen.insert(normalizedPath).inserted else { return }
            paths.append(url)
        }

        if let repoID = Repo.ID(rawValue: repoId) {
            appendUnique(modelDirectory(for: repoID))
        } else {
            let fallbackSubdirectory = repoId.replacingOccurrences(of: "/", with: "_")
            appendUnique(
                petalHubCache.cacheDirectory
                    .appendingPathComponent("mlx-audio")
                    .appendingPathComponent(fallbackSubdirectory)
            )
        }

        // Support direct model folders created by the downloader (`org--repo`) in addition
        // to linked MLX Audio cache folders (`org_repo`).
        appendUnique(
            petalHubCache.cacheDirectory
                .appendingPathComponent(repoId.replacingOccurrences(of: "/", with: "--"))
        )

        return paths
    }

    private static func hasDownloadedWeights(at modelDirectory: URL) -> Bool {
        let resolvedDirectory = modelDirectory.resolvingSymlinksInPath()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: resolvedDirectory.path) else {
            return false
        }

        guard let files = try? fileManager.contentsOfDirectory(
            at: resolvedDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return files.contains { file in
            guard file.pathExtension.lowercased() == "safetensors" else { return false }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            let size = values?.fileSize ?? 0
            return (values?.isRegularFile ?? true) && size > 0
        }
    }

    private static func modelDirectory(for repoID: Repo.ID) -> URL {
        let modelSubdirectory = repoID.description.replacingOccurrences(of: "/", with: "_")
        return petalHubCache.cacheDirectory
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
            size: size ?? "",
            quantization: quantization,
            parameters: parameters,
            recommended: recommended
        )
    }
}

private extension MLXPipelineModel {
    var qwenRepoID: String? {
        switch self {
        case .mini3b, .mini3b8bit, .parakeetTDT06BV3, .parakeetCTC06B, .whisperLargeV3Turbo, .whisperTiny:
            return nil
        case .qwen3ASR06B4bit:
            return "mlx-community/Qwen3-ASR-0.6B-4bit"
        }
    }

    var parakeetRepoID: String? {
        switch self {
        case .parakeetTDT06BV3:
            return "mlx-community/parakeet-tdt-0.6b-v3"
        case .parakeetCTC06B:
            return "mlx-community/parakeet-ctc-0.6b"
        case .mini3b, .mini3b8bit, .qwen3ASR06B4bit, .whisperLargeV3Turbo, .whisperTiny:
            return nil
        }
    }

    var whisperKitVariant: String? {
        switch self {
        case .whisperLargeV3Turbo:
            return "openai_whisper-large-v3_turbo"
        case .whisperTiny:
            return "openai_whisper-tiny"
        case .mini3b, .mini3b8bit, .qwen3ASR06B4bit, .parakeetTDT06BV3, .parakeetCTC06B:
            return nil
        }
    }

    var voxtralModel: VoxtralPipeline.Model {
        switch self {
        case .mini3b:
            return .mini3b
        case .mini3b8bit:
            return .mini3b8bit
        case .qwen3ASR06B4bit, .parakeetTDT06BV3, .parakeetCTC06B, .whisperLargeV3Turbo, .whisperTiny:
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
