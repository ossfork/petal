import Foundation

nonisolated enum HistoryRetentionMode: String, CaseIterable, Identifiable, Sendable {
    case none
    case transcripts
    case audio
    case both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "Off"
        case .transcripts:
            return "Transcripts"
        case .audio:
            return "Audio"
        case .both:
            return "Audio + Transcripts"
        }
    }

    var keepsHistory: Bool {
        self != .none
    }

    var keepsTranscripts: Bool {
        self == .transcripts || self == .both
    }

    var keepsAudio: Bool {
        self == .audio || self == .both
    }
}
