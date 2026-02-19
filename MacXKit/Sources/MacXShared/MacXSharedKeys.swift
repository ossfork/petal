import Sharing

public extension SharedKey where Self == AppStorageKey<Bool>.Default {
    static var hasCompletedSetup: Self {
        Self[.appStorage("has_completed_setup"), default: false]
    }
}

public extension SharedKey where Self == AppStorageKey<String>.Default {
    static var selectedModelID: Self {
        Self[.appStorage("selected_model_id"), default: MacXModelOption.defaultOption.rawValue]
    }

    static var transcriptionMode: Self {
        Self[.appStorage("transcription_mode"), default: MacXTranscriptionMode.verbatim.rawValue]
    }

    static var smartPrompt: Self {
        Self[.appStorage("smart_prompt"), default: "Clean up filler words and repeated phrases. Return a polished version of what was said."]
    }
}
