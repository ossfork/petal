import AVFoundation
import Dependencies
import Foundation
import os
import VoxtralCore

@MainActor
final class TranscriptionService {
    private var pipeline: VoxtralPipeline?
    private var loadedModel: ModelOption?
    @Dependency(\.appLogClient) private var appLogClient
    private let logger = Logger(subsystem: "com.optimalapps.macx", category: "TranscriptionService")

    func prepareModelIfNeeded(option: ModelOption) async throws {
        if loadedModel == option, pipeline != nil {
            logger.debug("Model already loaded: \(option.rawValue, privacy: .public)")
            return
        }

        unloadModel()
        logger.info("Loading model: \(option.rawValue, privacy: .public)")

        var config = VoxtralPipeline.Configuration.default
        config.temperature = 0.0
        config.topP = 0.95
        config.repetitionPenalty = 1.15

        let pipeline = VoxtralPipeline(
            model: option.pipelineModel,
            backend: .hybrid,
            configuration: config
        )

        let loadStart = Date()
        try await pipeline.loadModel()
        let loadDuration = Date().timeIntervalSince(loadStart)

        self.pipeline = pipeline
        self.loadedModel = option
        logger.info("Model loaded: \(option.rawValue, privacy: .public)")
        logger.info("Pipeline ready. encoderStatus=\(pipeline.encoderStatus, privacy: .public)")
        logger.info("Model load duration: \(loadDuration.formatted(.number.precision(.fractionLength(2))))s")
        logger.info("Power/Thermal state: lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled, privacy: .public), thermal=\(self.thermalStateDescription(ProcessInfo.processInfo.thermalState), privacy: .public)")
        consoleLog("Model loaded: \(option.rawValue)")
        consoleLog("Pipeline encoder status: \(pipeline.encoderStatus.replacingOccurrences(of: "\n", with: " | "))")
        consoleLog("Model load duration: \(loadDuration.formatted(.number.precision(.fractionLength(2))))s")
        consoleLog("Power/Thermal state: lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled), thermal=\(self.thermalStateDescription(ProcessInfo.processInfo.thermalState))")
    }

    func transcribe(audioURL: URL, option: ModelOption, mode: TranscriptionMode = .verbatim, prompt: String? = nil) async throws -> String {
        try await prepareModelIfNeeded(option: option)

        guard let pipeline else {
            throw TranscriptionError.pipelineUnavailable
        }

        let audioDuration = Self.audioDurationSeconds(audioURL)

        logger.info("Starting transcription for file: \(audioURL.lastPathComponent, privacy: .public)")
        logger.info("Inference config: backend=\(pipeline.backend.displayName, privacy: .public), language=en, mode=\(mode.rawValue, privacy: .public)")
        consoleLog("Starting transcription for file: \(audioURL.lastPathComponent)")
        consoleLog("Inference config: backend=\(pipeline.backend.displayName), language=en, mode=\(mode.rawValue)")

        let start = Date()
        let result: String
        switch mode {
        case .verbatim:
            result = try await pipeline.transcribe(audio: audioURL, language: "en")
        case .smart:
            let instruction = prompt ?? "Clean up filler words and repeated phrases. Return a polished version of what was said."
            result = try await pipeline.chat(audio: audioURL, prompt: instruction, language: "en")
        }
        let elapsed = Date().timeIntervalSince(start)
        let rtf = elapsed > 0 ? audioDuration / elapsed : 0

        logger.info("Finished transcription. characters=\(result.count, privacy: .public)")
        logger.info(
            "Transcription timing: audio=\(audioDuration.formatted(.number.precision(.fractionLength(2))))s, elapsed=\(elapsed.formatted(.number.precision(.fractionLength(2))))s, RTF=\(rtf.formatted(.number.precision(.fractionLength(2))))x"
        )
        logger.info("Encoder status after inference: \(pipeline.encoderStatus, privacy: .public)")
        logger.info("Memory summary: \(pipeline.memorySummary, privacy: .public)")
        logger.info("Power/Thermal state: lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled, privacy: .public), thermal=\(self.thermalStateDescription(ProcessInfo.processInfo.thermalState), privacy: .public)")
        consoleLog("Finished transcription. characters=\(result.count)")
        consoleLog(
            "Transcription timing: audio=\(audioDuration.formatted(.number.precision(.fractionLength(2))))s, elapsed=\(elapsed.formatted(.number.precision(.fractionLength(2))))s, RTF=\(rtf.formatted(.number.precision(.fractionLength(2))))x"
        )
        consoleLog("Encoder status after inference: \(pipeline.encoderStatus.replacingOccurrences(of: "\n", with: " | "))")
        consoleLog("Memory summary: \(pipeline.memorySummary)")
        consoleLog("Power/Thermal state: lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled), thermal=\(self.thermalStateDescription(ProcessInfo.processInfo.thermalState))")
        return result
    }

    func unloadModel() {
        pipeline?.unload()
        pipeline = nil
        loadedModel = nil
        logger.debug("Unloaded model pipeline")
    }

    func audioDurationSeconds(for url: URL) -> Double {
        Self.audioDurationSeconds(url)
    }

    private static func audioDurationSeconds(_ url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return Double(file.length) / sampleRate
    }

    private func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    private func consoleLog(_ message: String) {
        appLogClient.debug("TranscriptionPerf", message)
    }
}

enum TranscriptionError: LocalizedError {
    case pipelineUnavailable

    var errorDescription: String? {
        switch self {
        case .pipelineUnavailable:
            return "Transcription pipeline is not available."
        }
    }
}
