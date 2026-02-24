import Dependencies
import DependenciesMacros
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

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
                    return SystemLanguageModel.default.isAvailable
                }
                #endif
                return false
            },
            refine: { transcript, prompt in
                #if canImport(FoundationModels)
                if #available(macOS 26.0, *) {
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
                    return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                #endif
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
