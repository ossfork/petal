import Foundation

nonisolated struct TranscriptHistoryDay: Codable, Identifiable, Equatable, Sendable {
    var day: String
    var entries: [TranscriptHistoryEntry]

    var id: String { day }
}

nonisolated struct TranscriptHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var transcript: String
    var modelID: String
    var transcriptionMode: String
    var audioDurationSeconds: Double
    var transcriptionElapsedSeconds: Double
    var characterCount: Int
    var pasteResult: String
    var audioRelativePath: String?
    var transcriptRelativePath: String?
}
