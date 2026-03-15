@preconcurrency import AVFoundation
import Dependencies
import DependenciesMacros
import Foundation

enum AudioClientError: LocalizedError, Sendable {
    case notRecording
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .notRecording:
            return "No recording is currently active."
        case .failedToStart:
            return "Petal could not start recording audio."
        }
    }
}

@DependencyClient
public struct AudioClient: Sendable {
    public var isRecording: @Sendable () async -> Bool = { false }
    public var warmup: @Sendable () -> Void = {}
    public var startRecording: @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void
    public var stopRecording: @Sendable () async throws -> URL
    public var cancelRecording: @Sendable () async -> Void = {}
}

extension AudioClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            isRecording: {
                LiveAudioCaptureRuntimeContainer.shared.isRecording
            },
            warmup: {
                LiveAudioCaptureRuntimeContainer.shared.warmup()
            },
            startRecording: { levelHandler in
                try await LiveAudioCaptureRuntimeContainer.shared.startRecording(levelHandler: levelHandler)
            },
            stopRecording: {
                try await LiveAudioCaptureRuntimeContainer.shared.stopRecording()
            },
            cancelRecording: {
                await LiveAudioCaptureRuntimeContainer.shared.cancelRecording()
            }
        )
    }
}

extension AudioClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            isRecording: { false },
            warmup: {},
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

/// Thread-safe rolling-average level smoother, captured by the audio tap
/// closure so that `LiveAudioCaptureRuntime` is never referenced from the
/// real-time audio thread.
private final class LevelSmoother: @unchecked Sendable {
    private var levels: [Double] = []
    private let windowSize: Int
    private let lock = NSLock()

    init(windowSize: Int = 8) {
        self.windowSize = windowSize
    }

    func smooth(_ level: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        levels.append(level)
        if levels.count > windowSize {
            levels.removeFirst(levels.count - windowSize)
        }
        return levels.reduce(0, +) / Double(levels.count)
    }
}

private final class LiveAudioCaptureRuntime: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.petal.audio.capture.runtime")
    private var recorder: AVAudioRecorder?
    private var standbyRecorder: AVAudioRecorder?
    private var standbyURL: URL?
    private var simulatedRecordingSourceURL: URL?
    private var recordingURL: URL?
    private var levelHandler: @Sendable (Double) -> Void = { _ in }
    private var levelTimer: DispatchSourceTimer?
    private let levelSmoother = LevelSmoother()

    private nonisolated(unsafe) static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    var isRecording: Bool {
        stateQueue.sync {
            if simulatedRecordingSourceURL != nil {
                return true
            }
            return recorder?.isRecording ?? false
        }
    }

    /// Pre-creates and prepares an AVAudioRecorder so the next
    /// `startRecording` call only needs to call `record()`.
    func warmup() {
        stateQueue.async { [self] in
            warmupStandbyLocked()
        }
    }

    func startRecording(levelHandler: @escaping @Sendable (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                do {
                    try startRecordingLocked(levelHandler: levelHandler)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func warmupStandbyLocked() {
        guard standbyRecorder == nil, recorder == nil else { return }
        guard Self.e2eAudioFixtureURL() == nil else { return }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "petal-\(UUID().uuidString).wav")
        do {
            let rec = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
            rec.isMeteringEnabled = true
            guard rec.prepareToRecord() else { return }
            standbyRecorder = rec
            standbyURL = url
        } catch {}
    }

    private func startRecordingLocked(levelHandler: @escaping @Sendable (Double) -> Void) throws {
        guard recorder == nil, simulatedRecordingSourceURL == nil else { return }
        self.levelHandler = levelHandler

        if let e2eAudioURL = Self.e2eAudioFixtureURL() {
            simulatedRecordingSourceURL = e2eAudioURL
            recordingURL = e2eAudioURL
            startSimulatedLevelPollingLocked()
            return
        }

        // Use pre-warmed standby recorder if available
        if let standby = standbyRecorder, let url = standbyURL {
            standbyRecorder = nil
            standbyURL = nil
            guard standby.record() else {
                throw AudioClientError.failedToStart
            }
            self.recorder = standby
            recordingURL = url
            startLevelPollingLocked()
            return
        }

        // Fallback: create fresh recorder
        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "petal-\(UUID().uuidString).wav")

        let recorder = try AVAudioRecorder(url: audioURL, settings: Self.recordingSettings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw AudioClientError.failedToStart
        }

        self.recorder = recorder
        recordingURL = audioURL
        startLevelPollingLocked()
    }

    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async { [self] in
                do {
                    let url = try stopRecordingLocked()
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stopRecordingLocked() throws -> URL {
        if let fixtureURL = simulatedRecordingSourceURL {
            return try stopSimulatedRecordingLocked(sourceURL: fixtureURL)
        }

        guard let recorder, let url = recordingURL else {
            throw AudioClientError.notRecording
        }

        recorder.stop()
        stopLevelPollingLocked()
        self.recorder = nil
        recordingURL = nil
        levelHandler(0)

        // Pre-warm next standby recorder in the background
        stateQueue.asyncAfter(deadline: .now() + 0.1) { [self] in
            warmupStandbyLocked()
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0

        guard fileSize > 44 else {
            try? FileManager.default.removeItem(at: url)
            throw AudioClientError.failedToStart
        }

        return url
    }

    func cancelRecording() async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [self] in
                cancelRecordingLocked()
                continuation.resume()
            }
        }
    }

    private func cancelRecordingLocked() {
        if simulatedRecordingSourceURL != nil {
            stopLevelPollingLocked()
            simulatedRecordingSourceURL = nil
            recordingURL = nil
            levelHandler(0)
            return
        }

        guard let recorder else { return }

        recorder.stop()
        stopLevelPollingLocked()

        let url = recordingURL
        self.recorder = nil
        recordingURL = nil
        levelHandler(0)
        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        // Pre-warm next standby recorder in the background
        stateQueue.asyncAfter(deadline: .now() + 0.1) { [self] in
            warmupStandbyLocked()
        }
    }

    private func stopSimulatedRecordingLocked(sourceURL: URL) throws -> URL {
        stopLevelPollingLocked()
        simulatedRecordingSourceURL = nil
        recordingURL = nil
        levelHandler(0)

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "petal-e2e-\(UUID().uuidString).wav")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: outputURL)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
        guard fileSize > 44 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioClientError.failedToStart
        }
        return outputURL
    }

    private func startSimulatedLevelPollingLocked() {
        levelTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(60))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let smoothed = self.levelSmoother.smooth(0.34)
            let handler = self.levelHandler
            DispatchQueue.main.async {
                handler(smoothed)
            }
        }
        levelTimer = timer
        timer.resume()
    }

    private func startLevelPollingLocked() {
        levelTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(60))
        timer.setEventHandler { [weak self] in
            guard let self, let recorder = self.recorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let normalized = Self.normalizePower(power)
            let smoothed = self.levelSmoother.smooth(normalized)
            let handler = self.levelHandler
            DispatchQueue.main.async {
                handler(smoothed)
            }
        }
        levelTimer = timer
        timer.resume()
    }

    private func stopLevelPollingLocked() {
        levelTimer?.cancel()
        levelTimer = nil
    }

    nonisolated private static func normalizePower(_ power: Float) -> Double {
        if power <= -80 {
            return 0
        }
        let normalized = (Double(power) + 50.0) / 50.0
        return max(0, min(1, normalized))
    }

    nonisolated private static func e2eAudioFixtureURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["PETAL_E2E_AUDIO_FILE"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let path = UserDefaults.standard.string(forKey: "e2e_audio_file"), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }
}

private enum LiveAudioCaptureRuntimeContainer {
    static let shared = LiveAudioCaptureRuntime()
}
