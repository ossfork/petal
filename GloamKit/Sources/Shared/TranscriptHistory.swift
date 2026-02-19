import Foundation

public struct TranscriptHistoryDay: Codable, Identifiable, Equatable, Sendable {
    public var day: String
    public var entries: [TranscriptHistoryEntry]

    public var id: String { day }

    public init(day: String, entries: [TranscriptHistoryEntry]) {
        self.day = day
        self.entries = entries
    }
}

public struct TranscriptHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var transcript: String
    public var modelID: String
    public var transcriptionMode: String
    public var audioDurationSeconds: Double
    public var transcriptionElapsedSeconds: Double
    public var characterCount: Int
    public var pasteResult: String
    public var audioRelativePath: String?
    public var transcriptRelativePath: String?

    public init(
        id: UUID,
        timestamp: Date,
        transcript: String,
        modelID: String,
        transcriptionMode: String,
        audioDurationSeconds: Double,
        transcriptionElapsedSeconds: Double,
        characterCount: Int,
        pasteResult: String,
        audioRelativePath: String? = nil,
        transcriptRelativePath: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.transcript = transcript
        self.modelID = modelID
        self.transcriptionMode = transcriptionMode
        self.audioDurationSeconds = audioDurationSeconds
        self.transcriptionElapsedSeconds = transcriptionElapsedSeconds
        self.characterCount = characterCount
        self.pasteResult = pasteResult
        self.audioRelativePath = audioRelativePath
        self.transcriptRelativePath = transcriptRelativePath
    }
}
