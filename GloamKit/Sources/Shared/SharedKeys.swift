import Foundation
import Sharing

public extension SharedKey where Self == AppStorageKey<Bool>.Default {
    static var hasCompletedSetup: Self {
        Self[.appStorage("has_completed_setup"), default: false]
    }

    static var trimSilenceEnabled: Self {
        Self[.appStorage("trim_silence_enabled"), default: true]
    }

    static var autoSpeedEnabled: Self {
        Self[.appStorage("auto_speed_enabled"), default: true]
    }
}

public extension SharedKey where Self == AppStorageKey<String>.Default {
    static var selectedModelID: Self {
        Self[.appStorage("selected_model_id"), default: ModelOption.defaultOption.rawValue]
    }

    static var transcriptionMode: Self {
        Self[.appStorage("transcription_mode"), default: TranscriptionMode.verbatim.rawValue]
    }

    static var smartPrompt: Self {
        Self[.appStorage("smart_prompt"), default: "Clean up filler words and repeated phrases. Return a polished version of what was said."]
    }

    static var historyRetentionMode: Self {
        Self[.appStorage("history_retention_mode"), default: HistoryRetentionMode.both.rawValue]
    }
}

public extension SharedKey where Self == FileStorageKey<[TranscriptHistoryDay]>.Default {
    static var transcriptHistoryDays: Self {
        Self[
            .fileStorage(
                .documentsDirectory
                    .appending(component: "Gloam")
                    .appending(component: "history")
                    .appending(component: "history.json")
            ),
            default: []
        ]
    }
}
