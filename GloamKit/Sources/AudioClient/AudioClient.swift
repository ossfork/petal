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

/// Thread-safe rolling-average level smoother, captured by the audio tap
/// closure so that `LiveAudioCaptureRuntime` (which is `@MainActor`) is
/// never referenced from the real-time audio thread.
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

@MainActor
private final class LiveAudioCaptureRuntime {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var writeQueue: DispatchQueue?
    private var recordingURL: URL?
    private var levelHandler: @Sendable (Double) -> Void = { _ in }

    var isRecording: Bool {
        engine?.isRunning ?? false
    }

    func startRecording(levelHandler: @escaping @Sendable (Double) -> Void) throws {
        guard engine == nil else { return }
        self.levelHandler = levelHandler

        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "gloam-\(UUID().uuidString).wav")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioClientError.failedToStart
        }

        guard let recordFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioClientError.failedToStart
        }

        let audioFile = try AVAudioFile(forWriting: audioURL, settings: recordFormat.settings)
        let writeQueue = DispatchQueue(label: "com.gloam.audioWrite")

        // Install via nonisolated static so the closure doesn't inherit @MainActor
        Self.installTap(
            on: inputNode,
            format: recordFormat,
            audioFile: audioFile,
            writeQueue: writeQueue,
            smoother: LevelSmoother(),
            handler: levelHandler
        )

        engine.prepare()
        try engine.start()

        self.engine = engine
        self.audioFile = audioFile
        self.writeQueue = writeQueue
        recordingURL = audioURL
    }

    /// Installs the audio tap in a `nonisolated` context so the closure does
    /// NOT inherit `@MainActor` isolation — it runs on the audio render thread.
    nonisolated private static func installTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        audioFile: AVAudioFile,
        writeQueue: DispatchQueue,
        smoother: LevelSmoother,
        handler: @escaping @Sendable (Double) -> Void
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            writeQueue.async {
                try? audioFile.write(from: buffer)
            }
            let level = calculateLevel(from: buffer)
            let smoothed = smoother.smooth(level)
            DispatchQueue.main.async {
                handler(smoothed)
            }
        }
    }

    func stopRecording() throws -> URL {
        guard let engine, let url = recordingURL else {
            throw AudioClientError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writeQueue?.sync {}

        let fileLength = audioFile?.length ?? 0
        self.audioFile = nil

        self.engine = nil
        writeQueue = nil
        recordingURL = nil
        levelHandler(0)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
        print("[gloam-audio] stopRecording: length=\(fileLength) frames, fileSize=\(fileSize) bytes, path=\(url.lastPathComponent)")

        guard fileSize > 44 else {
            try? FileManager.default.removeItem(at: url)
            throw AudioClientError.failedToStart
        }

        return url
    }

    func cancelRecording() {
        guard let engine else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writeQueue?.sync {}

        let url = recordingURL
        self.engine = nil
        audioFile = nil
        writeQueue = nil
        recordingURL = nil
        levelHandler(0)
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func calculateLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        let data = channelData[0]
        for i in 0 ..< frames {
            let sample = data[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(max(rms, 1e-7))
        return Double(max(0, min(1, (db + 50) / 50)))
    }
}

@MainActor
private enum LiveAudioCaptureRuntimeContainer {
    static let shared = LiveAudioCaptureRuntime()
}
