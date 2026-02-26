import Testing
@testable import MLXClient

@Test
func detectsLoopedTranscript() {
    let looped = Array(repeating: "no", count: 80).joined(separator: ", ")
    #expect(QwenTranscriptGuard.isLikelyLooped(looped))
}

@Test
func allowsNormalTranscript() {
    let normal = "I reviewed the dashboard, fixed the missing button action, and pushed the update."
    #expect(!QwenTranscriptGuard.isLikelyLooped(normal))
}

@Test
func prefersHigherQualityTranscriptWhenBothLookLooped() {
    let primary = Array(repeating: "no", count: 40).joined(separator: " ")
    let fallback = "No no no no, I can hear you now and I am continuing with the rest of the sentence."
    #expect(QwenTranscriptGuard.preferredTranscript(primary: primary, fallback: fallback) == fallback)
}
