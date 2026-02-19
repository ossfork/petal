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
private final class LiveAudioCaptureRuntime: NSObject {
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var levelHandler: @Sendable (Double) -> Void = { _ in }
    private var rollingLevels: [Double] = []
    private let rollingWindowSize = 8

    var isRecording: Bool {
        recorder != nil
    }

    func startRecording(levelHandler: @escaping @Sendable (Double) -> Void) throws {
        guard recorder == nil else { return }

        self.levelHandler = levelHandler

        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "gloam-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: audioURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioClientError.failedToStart
        }

        self.recorder = recorder
        rollingLevels.removeAll(keepingCapacity: true)
        startMetering()
    }

    func stopRecording() throws -> URL {
        guard let recorder else {
            throw AudioClientError.notRecording
        }

        meterTask?.cancel()
        meterTask = nil

        recorder.stop()
        self.recorder = nil
        rollingLevels.removeAll(keepingCapacity: true)
        levelHandler(0)

        return recorder.url
    }

    func cancelRecording() {
        guard let recorder else { return }

        meterTask?.cancel()
        meterTask = nil

        let url = recorder.url
        recorder.stop()
        self.recorder = nil
        rollingLevels.removeAll(keepingCapacity: true)
        levelHandler(0)
        try? FileManager.default.removeItem(at: url)
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder else { return }

                recorder.updateMeters()
                let averagePower = recorder.averagePower(forChannel: 0)
                let normalized = max(0, min(1, (averagePower + 50) / 50))
                let smoothed = self.smoothedLevel(for: normalized)
                self.levelHandler(smoothed)

                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private func smoothedLevel(for newLevel: Float) -> Double {
        rollingLevels.append(Double(newLevel))

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
