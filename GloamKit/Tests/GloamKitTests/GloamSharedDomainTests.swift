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
func qwenModelIDsMapToQwenOption() {
    #expect(ModelOption.from(modelID: "qwen3-asr-0.6b") == .qwen3ASR06B4bit)
    #expect(ModelOption.from(modelID: "mlx-community/Qwen3-ASR-0.6B-4bit") == .qwen3ASR06B4bit)
}

@Test
func whisperModelIDsMapToWhisperOptions() {
    #expect(ModelOption.from(modelID: "whisper-large-v3") == .whisperLargeV3TurboASRFP16)
    #expect(ModelOption.from(modelID: "mlx-community/whisper-large-v3-turbo-asr-fp16") == .whisperLargeV3TurboASRFP16)
    #expect(ModelOption.from(modelID: "whisper-tiny") == .whisperTinyMLX)
    #expect(ModelOption.from(modelID: "mlx-community/whisper-tiny-mlx") == .whisperTinyMLX)
}

@Test
func modelOptionDescriptorMatchesRawValue() {
    for option in ModelOption.allCases {
        #expect(option.descriptor.id == option.rawValue)
    }
}

@Test
func modelCatalogIncludesBothBackends() {
    #expect(ModelOption.allCases.contains(.mini3b))
    #expect(ModelOption.allCases.contains(.qwen3ASR06B4bit))
    #expect(ModelOption.allCases.contains(.whisperLargeV3TurboASRFP16))
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

@Test
func qwenSupportsVerbatimOnly() {
    #expect(ModelOption.qwen3ASR06B4bit.supportedTranscriptionModes == [.verbatim])
    #expect(!ModelOption.qwen3ASR06B4bit.supportsSmartTranscription)
}

@Test
func whisperSupportsVerbatimOnly() {
    #expect(ModelOption.whisperLargeV3TurboASRFP16.supportedTranscriptionModes == [.verbatim])
    #expect(!ModelOption.whisperLargeV3TurboASRFP16.supportsSmartTranscription)
    #expect(ModelOption.whisperTinyMLX.supportedTranscriptionModes == [.verbatim])
    #expect(!ModelOption.whisperTinyMLX.supportsSmartTranscription)
    #expect(ModelOption.whisperLargeV3TurboASRFP16.providerDisplayName == "OpenAI Whisper")
}

@Test
func voxtralSupportsSmartAndVerbatim() {
    #expect(ModelOption.mini3b.supportedTranscriptionModes.contains(.verbatim))
    #expect(ModelOption.mini3b.supportedTranscriptionModes.contains(.smart))
    #expect(ModelOption.mini3b.supportsSmartTranscription)
}
