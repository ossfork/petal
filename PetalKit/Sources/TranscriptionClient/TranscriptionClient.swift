import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import AudioSpeedClient
import AudioTrimClient
import MLXClient
import Shared
#if canImport(Speech)
import Speech
#endif

@DependencyClient
public struct TranscriptionClient: Sendable {
    public var prepareModelIfNeeded: @Sendable (ModelOption) async throws -> Void
    public var transcribe: @Sendable (URL, ModelOption, TranscriptionMode, String?) async throws -> String
    public var unloadModel: @Sendable () async -> Void = {}
    public var audioDurationSeconds: @Sendable (URL) -> Double = { _ in 0 }
}

extension TranscriptionClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            prepareModelIfNeeded: { option in
                guard option.requiresDownload else { return }
                @Dependency(\.mlxClient) var mlxClient
                guard let pipelineModel = option.pipelineModel else { return }
                try await mlxClient.prepareModelIfNeeded(pipelineModel)
            },
            transcribe: { audioURL, option, mode, prompt in
                @Dependency(\.mlxClient) var mlxClient
                @Dependency(\.audioTrimClient) var trimClient
                @Dependency(\.audioSpeedClient) var speedClient
                if option.requiresDownload, let pipelineModel = option.pipelineModel {
                    try await mlxClient.prepareModelIfNeeded(pipelineModel)
                }

                @Shared(.trimSilenceEnabled) var trimEnabled
                @Shared(.autoSpeedEnabled) var speedEnabled

                var workingAudioURL = audioURL
                var generatedAudioURLs = Set<URL>()

                if trimEnabled {
                    let trimmedURL = try await trimClient.trimSilence(workingAudioURL, Self.trimSilenceThreshold)
                    if trimmedURL != workingAudioURL {
                        generatedAudioURLs.insert(trimmedURL)
                        workingAudioURL = trimmedURL
                    }
                }

                let duration = await audioFileDurationSecondsAsync(workingAudioURL)
                if speedEnabled, let speedRate = Self.autoSpeedRate(for: duration) {
                    let spedUpURL = try await speedClient.speedUp(workingAudioURL, speedRate)
                    if spedUpURL != workingAudioURL {
                        generatedAudioURLs.insert(spedUpURL)
                        workingAudioURL = spedUpURL
                    }
                }

                defer {
                    for generatedURL in generatedAudioURLs {
                        try? FileManager.default.removeItem(at: generatedURL)
                    }
                }

                if option == .appleSpeech {
                    return try await Self.transcribeWithAppleSpeech(workingAudioURL)
                }

                return try await mlxClient.transcribe(
                    workingAudioURL,
                    mode == .verbatim
                        ? .verbatim
                        : .smart(prompt: prompt ?? Self.defaultSmartPrompt)
                )
            },
            unloadModel: {
                @Dependency(\.mlxClient) var mlxClient
                await mlxClient.unloadModel()
            },
            audioDurationSeconds: { url in
                audioFileDurationSeconds(url)
            }
        )
    }
}

extension TranscriptionClient: TestDependencyKey {
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
    var transcriptionClient: TranscriptionClient {
        get { self[TranscriptionClient.self] }
        set { self[TranscriptionClient.self] = newValue }
    }
}

private func audioFileDurationSeconds(_ url: URL) -> Double {
    guard let file = try? AVAudioFile(forReading: url) else { return 0 }
    let sampleRate = file.fileFormat.sampleRate
    guard sampleRate > 0 else { return 0 }
    return Double(file.length) / sampleRate
}

private func audioFileDurationSecondsAsync(_ url: URL) async -> Double {
    await Task.detached(priority: .utility) {
        audioFileDurationSeconds(url)
    }.value
}

private extension TranscriptionClient {
    static let defaultSmartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said."
    static let trimSilenceThreshold: Float = 0.003

    static func autoSpeedRate(for audioDuration: Double) -> Double? {
        switch audioDuration {
        case ..<45:
            return nil
        case 45..<90:
            return 1.1
        case 90..<180:
            return 1.2
        default:
            return 1.25
        }
    }
}

private extension ModelOption {
    var pipelineModel: MLXPipelineModel? {
        switch self {
        case .appleSpeech:
            return nil
        case .qwen3ASR06B4bit:
            return .qwen3ASR06B4bit
        case .whisperLargeV3Turbo:
            return .whisperLargeV3Turbo
        case .whisperTiny:
            return .whisperTiny
        case .mini3b:
            return .mini3b
        case .mini3b8bit:
            return .mini3b8bit
        }
    }
}

private extension TranscriptionClient {
    static func transcribeWithAppleSpeech(_ audioURL: URL) async throws -> String {
        #if canImport(Speech)
        if #available(macOS 26, *) {
            return try await AppleSpeechRuntime.transcribe(audioURL: audioURL)
        }
        #endif
        throw AppleSpeechError.unavailable
    }
}

#if canImport(Speech)
@available(macOS 26, *)
private enum AppleSpeechRuntime {
    static func transcribe(audioURL: URL) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechError.unavailable
        }

        let supportedLocales = await SpeechTranscriber.supportedLocales
        let installedLocales = await SpeechTranscriber.installedLocales

        let supportedIDs = Set(supportedLocales.map(normalizedLocaleIdentifier))
        let installedSupportedLocales = installedLocales.filter { locale in
            supportedIDs.contains(normalizedLocaleIdentifier(locale))
        }

        guard !installedSupportedLocales.isEmpty else {
            throw AppleSpeechError.noInstalledLocale
        }

        let locale = preferredLocale(from: installedSupportedLocales)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: audioURL)
        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

        var transcript = AttributedString()
        for try await result in transcriber.results {
            transcript += result.text
        }

        let text = String(transcript.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AppleSpeechError.emptyTranscript
        }
        return text
    }

    private static func preferredLocale(from locales: [Locale]) -> Locale {
        let current = normalizedLocaleIdentifier(Locale.current)
        if let exactMatch = locales.first(where: { normalizedLocaleIdentifier($0) == current }) {
            return exactMatch
        }

        if let currentLanguage = Locale.current.language.languageCode?.identifier.lowercased(),
           let languageMatch = locales.first(where: {
               $0.language.languageCode?.identifier.lowercased() == currentLanguage
           })
        {
            return languageMatch
        }

        return locales[0]
    }

    private static func normalizedLocaleIdentifier(_ locale: Locale) -> String {
        locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }
}
#endif

private enum AppleSpeechError: LocalizedError {
    case unavailable
    case noInstalledLocale
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Speech is not available on this Mac."
        case .noInstalledLocale:
            return "No installed Apple Speech locale is available. Add a dictation language in System Settings."
        case .emptyTranscript:
            return "No speech detected."
        }
    }
}
