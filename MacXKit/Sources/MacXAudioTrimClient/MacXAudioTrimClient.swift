import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct MacXAudioTrimClient: Sendable {
    public var trimSilence: @Sendable (_ audioURL: URL, _ threshold: Float) async throws -> URL
}

extension MacXAudioTrimClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            trimSilence: { audioURL, threshold in
                try await Task.detached(priority: .userInitiated) {
                    let input = try loadMonoFloatSamples(from: audioURL)
                    guard !input.samples.isEmpty else { return audioURL }

                    let clampedThreshold = max(0.0001, threshold)
                    guard let start = input.samples.firstIndex(where: { abs($0) > clampedThreshold }),
                          let end = input.samples.lastIndex(where: { abs($0) > clampedThreshold }),
                          start < end
                    else {
                        return audioURL
                    }

                    let trimmed = Array(input.samples[start...end])
                    return try writeMonoFloatSamples(trimmed, sampleRate: input.sampleRate, filePrefix: "macx-trim")
                }.value
            }
        )
    }
}

extension MacXAudioTrimClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            trimSilence: { audioURL, _ in audioURL }
        )
    }
}

public extension DependencyValues {
    var macXAudioTrimClient: MacXAudioTrimClient {
        get { self[MacXAudioTrimClient.self] }
        set { self[MacXAudioTrimClient.self] = newValue }
    }
}

private struct MonoFloatAudioData {
    let samples: [Float]
    let sampleRate: Double
}

private func loadMonoFloatSamples(from url: URL) throws -> MonoFloatAudioData {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let frameCapacity = AVAudioFrameCount(file.length)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
        throw MacXAudioTrimError.bufferAllocationFailed
    }

    try file.read(into: buffer)

    guard let channelData = buffer.floatChannelData else {
        throw MacXAudioTrimError.unsupportedAudioFormat
    }

    let frameLength = Int(buffer.frameLength)
    let firstChannel = channelData[0]
    let samples = Array(UnsafeBufferPointer(start: firstChannel, count: frameLength))

    return MonoFloatAudioData(samples: samples, sampleRate: format.sampleRate)
}

private func writeMonoFloatSamples(_ samples: [Float], sampleRate: Double, filePrefix: String) throws -> URL {
    let outputURL = FileManager.default.temporaryDirectory
        .appending(path: "\(filePrefix)-\(UUID().uuidString).wav")

    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
          let channelData = buffer.floatChannelData?[0]
    else {
        throw MacXAudioTrimError.bufferAllocationFailed
    }

    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, value) in samples.enumerated() {
        channelData[index] = value
    }

    let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    try file.write(from: buffer)
    return outputURL
}

private enum MacXAudioTrimError: LocalizedError {
    case unsupportedAudioFormat
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedAudioFormat:
            return "Unsupported audio format for silence trimming."
        case .bufferAllocationFailed:
            return "Could not allocate audio buffers for silence trimming."
        }
    }
}
