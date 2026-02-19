import Testing
@testable import MacXShared

@Test
func modelOptionFallbackUsesDefault() {
    #expect(MacXModelOption.from(modelID: "unknown-id") == .defaultOption)
}

@Test
func modelOptionDescriptorMatchesRawValue() {
    for option in MacXModelOption.allCases {
        #expect(option.descriptor.id == option.rawValue)
    }
}

@Test
func defaultModelRemainsRecommended() {
    #expect(MacXModelOption.defaultOption.isRecommended)
}

@Test
func transcriptionModeDisplayTextStable() {
    #expect(MacXTranscriptionMode.verbatim.displayName == "Verbatim")
    #expect(MacXTranscriptionMode.smart.displayName == "Smart")
}
