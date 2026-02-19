import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation
import MacXAudioSpeedClient
import MacXAudioTrimClient
import MacXMLXClient
import MacXShared

@DependencyClient
public struct MacXTranscriptionClient: Sendable {
    public var prepareModelIfNeeded: @Sendable (MacXModelOption) async throws -> Void
    public var transcribe: @Sendable (URL, MacXModelOption, MacXTranscriptionMode, String?) async throws -> String
    public var unloadModel: @Sendable () async -> Void = {}
    public var audioDurationSeconds: @Sendable (URL) -> Double = { _ in 0 }
}

extension MacXTranscriptionClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            prepareModelIfNeeded: { option in
                @Dependency(\.macXMLXClient) var mlxClient
                try await mlxClient.prepareModelIfNeeded(option.pipelineModel)
            },
            transcribe: { audioURL, option, mode, prompt in
                @Dependency(\.macXMLXClient) var mlxClient
                @Dependency(\.macXAudioTrimClient) var trimClient
                @Dependency(\.macXAudioSpeedClient) var speedClient
                try await mlxClient.prepareModelIfNeeded(option.pipelineModel)

                var workingAudioURL = audioURL
                var generatedAudioURLs = Set<URL>()

                if Self.trimSilenceEnabled {
                    let trimmedURL = try await trimClient.trimSilence(workingAudioURL, Self.trimSilenceThreshold)
                    if trimmedURL != workingAudioURL {
                        generatedAudioURLs.insert(trimmedURL)
                        workingAudioURL = trimmedURL
                    }
                }

                let duration = audioFileDurationSeconds(workingAudioURL)
                if let speedRate = Self.autoSpeedRate(for: duration) {
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

                return try await mlxClient.transcribe(
                    workingAudioURL,
                    mode == .verbatim
                        ? .verbatim
                        : .smart(prompt: prompt ?? Self.defaultSmartPrompt)
                )
            },
            unloadModel: {
                @Dependency(\.macXMLXClient) var mlxClient
                await mlxClient.unloadModel()
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

private func audioFileDurationSeconds(_ url: URL) -> Double {
    guard let file = try? AVAudioFile(forReading: url) else { return 0 }
    let sampleRate = file.fileFormat.sampleRate
    guard sampleRate > 0 else { return 0 }
    return Double(file.length) / sampleRate
}

private extension MacXTranscriptionClient {
    static let defaultSmartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said."
    static let trimSilenceEnabled = true
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

private extension MacXModelOption {
    var pipelineModel: MacXMLXPipelineModel {
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
