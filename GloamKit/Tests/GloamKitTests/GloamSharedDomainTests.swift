import Testing
@testable import GloamShared

@Test
func modelOptionFallbackUsesDefault() {
    #expect(GloamModelOption.from(modelID: "unknown-id") == .defaultOption)
}

@Test
func modelOptionDescriptorMatchesRawValue() {
    for option in GloamModelOption.allCases {
        #expect(option.descriptor.id == option.rawValue)
    }
}

@Test
func defaultModelRemainsRecommended() {
    #expect(GloamModelOption.defaultOption.isRecommended)
}

@Test
func transcriptionModeDisplayTextStable() {
    #expect(GloamTranscriptionMode.verbatim.displayName == "Verbatim")
    #expect(GloamTranscriptionMode.smart.displayName == "Smart")
}
