import Foundation
import Sharing

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    static var hasCompletedSetup: Self {
        Self[.appStorage("has_completed_setup"), default: false]
    }
}

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var selectedModelID: Self {
        Self[.appStorage("selected_model_id"), default: "mini-3b-8bit"]
    }

    static var transcriptionMode: Self {
        Self[.appStorage("transcription_mode"), default: TranscriptionMode.verbatim.rawValue]
    }

    static var smartPrompt: Self {
        Self[.appStorage("smart_prompt"), default: "Clean up filler words and repeated phrases. Return a polished version of what was said."]
    }
}

extension SharedKey where Self == FileStorageKey<[TranscriptHistoryDay]>.Default {
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

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var historyRetentionMode: Self {
        Self[.appStorage("history_retention_mode"), default: HistoryRetentionMode.both.rawValue]
    }
}
