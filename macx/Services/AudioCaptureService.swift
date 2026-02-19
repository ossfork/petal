import AVFoundation
import Dependencies
import Foundation
import IssueReporting
import os

@MainActor
final class AudioCaptureService: NSObject {
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var levelHandler: @Sendable (Double) -> Void = { _ in }
    private let logger = Logger(subsystem: "com.optimalapps.macx", category: "AudioCaptureService")
    private var rollingLevels: [Double] = []
    private let rollingWindowSize = 8

    @Dependency(\.uuid) private var uuid

    var isRecording: Bool {
        recorder != nil
    }

    func startRecording(levelHandler: @escaping @Sendable (Double) -> Void) throws {
        guard recorder == nil else { return }

        self.levelHandler = levelHandler

        let audioURL = FileManager.default.temporaryDirectory
            .appending(path: "macx-\(uuid().uuidString).m4a")

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
            reportIssue("AVAudioRecorder failed to start recording.")
            throw AudioCaptureError.failedToStart
        }

        self.recorder = recorder
        rollingLevels.removeAll(keepingCapacity: true)
        startMetering()
        logger.info("Recording started. file=\(audioURL.lastPathComponent, privacy: .public)")
    }

    func stopRecording() throws -> URL {
        guard let recorder else {
            throw AudioCaptureError.notRecording
        }

        meterTask?.cancel()
        meterTask = nil

        recorder.stop()
        self.recorder = nil

        rollingLevels.removeAll(keepingCapacity: true)
        levelHandler(0)
        logger.info("Recording stopped. file=\(recorder.url.lastPathComponent, privacy: .public)")

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
        logger.info("Recording canceled. file=\(url.lastPathComponent, privacy: .public)")
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

enum AudioCaptureError: LocalizedError {
    case notRecording
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .notRecording:
            return "No recording is currently active."
        case .failedToStart:
            return "MacX could not start recording audio."
        }
    }
}
