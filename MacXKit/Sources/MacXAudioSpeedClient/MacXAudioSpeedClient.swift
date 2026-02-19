import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct MacXAudioSpeedClient: Sendable {
    public var speedUp: @Sendable (_ audioURL: URL, _ rate: Double) async throws -> URL
}

extension MacXAudioSpeedClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            speedUp: { audioURL, rate in
                try await Task.detached(priority: .userInitiated) {
                    guard rate > 1.0 else { return audioURL }

                    let input = try loadMonoFloatSamples(from: audioURL)
                    guard input.samples.count > 4 else { return audioURL }

                    let outputLength = max(1, Int(Double(input.samples.count) / rate))
                    let spedUp = resample(samples: input.samples, outputLength: outputLength, speed: rate)
                    return try writeMonoFloatSamples(spedUp, sampleRate: input.sampleRate, filePrefix: "macx-speed")
                }.value
            }
        )
    }
}

extension MacXAudioSpeedClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            speedUp: { audioURL, _ in audioURL }
        )
    }
}

public extension DependencyValues {
    var macXAudioSpeedClient: MacXAudioSpeedClient {
        get { self[MacXAudioSpeedClient.self] }
        set { self[MacXAudioSpeedClient.self] = newValue }
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
        throw MacXAudioSpeedError.bufferAllocationFailed
    }

    try file.read(into: buffer)

    guard let channelData = buffer.floatChannelData else {
        throw MacXAudioSpeedError.unsupportedAudioFormat
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
        throw MacXAudioSpeedError.bufferAllocationFailed
    }

    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, value) in samples.enumerated() {
        channelData[index] = value
    }

    let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    try file.write(from: buffer)
    return outputURL
}

private func resample(samples: [Float], outputLength: Int, speed: Double) -> [Float] {
    guard outputLength > 0 else { return [] }
    var output = Array(repeating: Float(0), count: outputLength)

    for index in 0..<outputLength {
        let sourcePosition = Double(index) * speed
        let left = Int(sourcePosition.rounded(.down))
        let right = min(left + 1, samples.count - 1)
        let fraction = Float(sourcePosition - Double(left))

        if left >= samples.count {
            output[index] = samples[samples.count - 1]
        } else {
            output[index] = samples[left] * (1 - fraction) + samples[right] * fraction
        }
    }

    return output
}

private enum MacXAudioSpeedError: LocalizedError {
    case unsupportedAudioFormat
    case bufferAllocationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedAudioFormat:
            return "Unsupported audio format for speed-up processing."
        case .bufferAllocationFailed:
            return "Could not allocate audio buffers for speed-up processing."
        }
    }
}
