import Foundation

public enum HistoryRetentionMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case none
    case transcripts
    case audio
    case both

    public var id: String { rawValue }

    public var displayName: String {
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

    public var keepsHistory: Bool {
        self != .none
    }

    public var keepsTranscripts: Bool {
        self == .transcripts || self == .both
    }

    public var keepsAudio: Bool {
        self == .audio || self == .both
    }
}
