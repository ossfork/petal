import Testing
@testable import Shared

@Test
func modelOptionFallbackUsesDefault() {
    #expect(ModelOption.from(modelID: "unknown-id") == .defaultOption)
}

@Test
func legacyModelIDsMapToValidatedModel() {
    #expect(ModelOption.from(modelID: "mini-3b-8bit") == .mini3b)
    #expect(ModelOption.from(modelID: "mini-3b-4bit") == .mini3b)
}

@Test
func modelOptionDescriptorMatchesRawValue() {
    for option in ModelOption.allCases {
        #expect(option.descriptor.id == option.rawValue)
    }
}

@Test
func defaultModelRemainsRecommended() {
    #expect(ModelOption.defaultOption.isRecommended)
}

@Test
func transcriptionModeDisplayTextStable() {
    #expect(TranscriptionMode.verbatim.displayName == "Verbatim")
    #expect(TranscriptionMode.smart.displayName == "Smart")
}
