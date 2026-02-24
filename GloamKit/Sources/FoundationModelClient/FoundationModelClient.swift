import Dependencies
import DependenciesMacros
import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.optimalapps.gloam", category: "FoundationModelClient")

@DependencyClient
public struct FoundationModelClient: Sendable {
    public var isAvailable: @Sendable () -> Bool = { false }
    public var refine: @Sendable (_ transcript: String, _ prompt: String) async throws -> String
}

extension FoundationModelClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            isAvailable: {
                #if canImport(FoundationModels)
                if #available(macOS 26.0, *) {
                    let available = SystemLanguageModel.default.isAvailable
                    let availability = SystemLanguageModel.default.availability
                    logger.info("Foundation Models availability check: isAvailable=\(available, privacy: .public), availability=\(String(describing: availability), privacy: .public)")
                    return available
                } else {
                    logger.info("Foundation Models unavailable: macOS version < 26.0")
                    return false
                }
                #else
                logger.info("Foundation Models unavailable: FoundationModels module not importable")
                return false
                #endif
            },
            refine: { transcript, prompt in
                #if canImport(FoundationModels)
                if #available(macOS 26.0, *) {
                    guard SystemLanguageModel.default.isAvailable else {
                        logger.warning("refine called but Foundation Models not available at runtime, returning original transcript")
                        return transcript
                    }

                    let inputLength = transcript.count
                    logger.info("Starting Foundation Model refinement: inputLength=\(inputLength, privacy: .public), promptLength=\(prompt.count, privacy: .public)")

                    let start = ContinuousClock.now
                    let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
                    let session = LanguageModelSession(
                        model: model,
                        instructions: """
                        You are a transcription post-processor. Your job is to clean up speech-to-text output.
                        Apply the user's instructions to refine the transcript.
                        Return ONLY the refined text with no preamble, explanation, or commentary.
                        Preserve the original meaning and content.
                        """
                    )
                    let response = try await session.respond(
                        to: """
                        Instructions: \(prompt)

                        Transcript to refine:
                        \(transcript)
                        """
                    )
                    let elapsed = ContinuousClock.now - start
                    let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    logger.info("Foundation Model refinement complete: elapsed=\(elapsed, privacy: .public), outputLength=\(result.count, privacy: .public)")
                    return result
                }
                #endif
                logger.warning("refine called but FoundationModels not compiled in, returning original transcript")
                return transcript
            }
        )
    }
}

extension FoundationModelClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            isAvailable: { false },
            refine: { transcript, _ in transcript }
        )
    }
}

public extension DependencyValues {
    var foundationModelClient: FoundationModelClient {
        get { self[FoundationModelClient.self] }
        set { self[FoundationModelClient.self] = newValue }
    }
}
