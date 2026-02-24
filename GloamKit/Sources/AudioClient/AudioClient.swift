import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation

public enum AudioClientError: LocalizedError, Sendable {
    case notRecording
    case failedToStart

    public var errorDescription: String? {
        switch self {
        case .notRecording:
            return "No recording is currently active."
        case .failedToStart:
            return "Gloam could not start recording audio."
        }
    }
}

@DependencyClient
public struct AudioClient: Sendable {
    public var isRecording: @Sendable () async -> Bool = { false }
    public var startRecording: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void
    public var stopRecording: @Sendable () async throws -> URL
    public var cancelRecording: @Sendable () async -> Void = {}
}

extension AudioClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            isRecording: {
                await MainActor.run { LiveAudioCaptureRuntimeContainer.shared.isRecording }
            },
            startRecording: { levelHandler in
                try await MainActor.run { try LiveAudioCaptureRuntimeContainer.shared.startRecording(levelHandler: levelHandler) }
            },
            stopRecording: {
                try await MainActor.run { try LiveAudioCaptureRuntimeContainer.shared.stopRecording() }
            },
            cancelRecording: {
                await MainActor.run { LiveAudioCaptureRuntimeContainer.shared.cancelRecording() }
            }
        )
    }
}

extension AudioClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            isRecording: { false },
            startRecording: { _ in },
            stopRecording: { URL(fileURLWithPath: "/dev/null") },
            cancelRecording: {}
        )
    }
}

public extension DependencyValues {
    var audioClient: AudioClient {
        get { self[AudioClient.self] }
        set { self[AudioClient.self] = newValue }
    }
}

@MainActor
private final class LiveAudioCaptureRuntime {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var writeQueue: DispatchQueue?
    private var recordingURL: URL?
    private var levelHandler: @Sendable (Double) -> Void = { _ in }
    private var rollingLevels: [Double] = []
    private let rollingWindowSize = 8

    var isRecording: Bool {
        engine?.isRunning ?? false
    }

    func startRecording(levelHandler: @escaping @Sendable (Double) -> Void) throws {
        guard engine == nil else { return }
        self.levelHandler = levelHandler

        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "gloam-\(UUID().uuidString).m4a")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let audioFile = try AVAudioFile(
            forWriting: audioURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
        )

        let writeQueue = DispatchQueue(label: "com.gloam.audioWrite")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            writeQueue.async {
                try? audioFile.write(from: buffer)
            }
            let level = Self.calculateLevel(from: buffer)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let smoothed = self.smoothedLevel(for: level)
                self.levelHandler(smoothed)
            }
        }

        engine.prepare()
        try engine.start()

        self.engine = engine
        self.audioFile = audioFile
        self.writeQueue = writeQueue
        self.recordingURL = audioURL
        rollingLevels.removeAll(keepingCapacity: true)
    }

    func stopRecording() throws -> URL {
        guard let engine, let url = recordingURL else {
            throw AudioClientError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writeQueue?.sync {}

        self.engine = nil
        self.audioFile = nil
        self.writeQueue = nil
        self.recordingURL = nil
        rollingLevels.removeAll(keepingCapacity: true)
        levelHandler(0)

        return url
    }

    func cancelRecording() {
        guard let engine else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writeQueue?.sync {}

        let url = recordingURL
        self.engine = nil
        self.audioFile = nil
        self.writeQueue = nil
        self.recordingURL = nil
        rollingLevels.removeAll(keepingCapacity: true)
        levelHandler(0)
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func calculateLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        let data = channelData[0]
        for i in 0..<frames {
            let sample = data[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(max(rms, 1e-7))
        return Double(max(0, min(1, (db + 50) / 50)))
    }

    private func smoothedLevel(for newLevel: Double) -> Double {
        rollingLevels.append(newLevel)
        if rollingLevels.count > rollingWindowSize {
            rollingLevels.removeFirst(rollingLevels.count - rollingWindowSize)
        }
        let sum = rollingLevels.reduce(0, +)
        return sum / Double(rollingLevels.count)
    }
}

@MainActor
private enum LiveAudioCaptureRuntimeContainer {
    static let shared = LiveAudioCaptureRuntime()
}
