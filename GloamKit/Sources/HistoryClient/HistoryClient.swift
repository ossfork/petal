import AppKit
import Dependencies
import DependenciesMacros
import Foundation
import Shared

@DependencyClient
public struct HistoryClient: Sendable {
    public var bootstrap: @Sendable (HistoryRetentionMode, [TranscriptHistoryDay]) -> [TranscriptHistoryDay] = { _, days in days }
    public var applyRetention: @Sendable (HistoryRetentionMode, [TranscriptHistoryDay]) -> [TranscriptHistoryDay] = { _, days in days }
    public var appendEntry: @Sendable (AppendEntryRequest) -> [TranscriptHistoryDay] = { _ in [] }
    public var persistArtifacts: @Sendable (PersistArtifactsRequest) -> PersistedArtifacts? = { _ in nil }
    public var openHistoryFolder: @Sendable (HistoryRetentionMode) -> Bool = { _ in false }
    public var historyAudioURL: @Sendable (String?) -> URL? = { _ in nil }
    public var modelsDirectoryPath: @Sendable () -> String = { "" }
    public var historyDirectoryPath: @Sendable () -> String = { "" }
}

public struct AppendEntryRequest: Sendable {
    public var currentDays: [TranscriptHistoryDay]
    public var transcript: String
    public var modelID: String
    public var mode: String
    public var audioDuration: Double
    public var transcriptionElapsed: Double
    public var pasteResult: String
    public var audioRelativePath: String?
    public var transcriptRelativePath: String?
    public var retentionMode: HistoryRetentionMode
    public var timestamp: Date
    public var id: UUID

    public init(
        currentDays: [TranscriptHistoryDay],
        transcript: String,
        modelID: String,
        mode: String,
        audioDuration: Double,
        transcriptionElapsed: Double,
        pasteResult: String,
        audioRelativePath: String?,
        transcriptRelativePath: String?,
        retentionMode: HistoryRetentionMode,
        timestamp: Date,
        id: UUID
    ) {
        self.currentDays = currentDays
        self.transcript = transcript
        self.modelID = modelID
        self.mode = mode
        self.audioDuration = audioDuration
        self.transcriptionElapsed = transcriptionElapsed
        self.pasteResult = pasteResult
        self.audioRelativePath = audioRelativePath
        self.transcriptRelativePath = transcriptRelativePath
        self.retentionMode = retentionMode
        self.timestamp = timestamp
        self.id = id
    }
}

public struct PersistArtifactsRequest: Sendable {
    public var audioURL: URL
    public var transcript: String
    public var timestamp: Date
    public var mode: String
    public var modelID: String
    public var retentionMode: HistoryRetentionMode

    public init(
        audioURL: URL,
        transcript: String,
        timestamp: Date,
        mode: String,
        modelID: String,
        retentionMode: HistoryRetentionMode
    ) {
        self.audioURL = audioURL
        self.transcript = transcript
        self.timestamp = timestamp
        self.mode = mode
        self.modelID = modelID
        self.retentionMode = retentionMode
    }
}

public struct PersistedArtifacts: Sendable {
    public var audioRelativePath: String?
    public var transcriptRelativePath: String?

    public init(audioRelativePath: String? = nil, transcriptRelativePath: String? = nil) {
        self.audioRelativePath = audioRelativePath
        self.transcriptRelativePath = transcriptRelativePath
    }
}

extension HistoryClient: DependencyKey {
    public static var liveValue: Self {
        let runtime = HistoryRuntime()
        return Self(
            bootstrap: { retentionMode, storedDays in
                runtime.applyRetention(retentionMode, to: storedDays)
            },
            applyRetention: { retentionMode, currentDays in
                runtime.applyRetention(retentionMode, to: currentDays)
            },
            appendEntry: { request in
                runtime.appendEntry(request)
            },
            persistArtifacts: { request in
                runtime.persistArtifacts(request)
            },
            openHistoryFolder: { retentionMode in
                runtime.openHistoryFolder(retentionMode: retentionMode)
            },
            historyAudioURL: { relativePath in
                runtime.historyAudioURL(relativePath: relativePath)
            },
            modelsDirectoryPath: {
                runtime.modelsDirectoryPath
            },
            historyDirectoryPath: {
                runtime.historyDirectoryPath
            }
        )
    }
}

extension HistoryClient: TestDependencyKey {
    public static var testValue: Self {
        Self()
    }
}

public extension DependencyValues {
    var historyClient: HistoryClient {
        get { self[HistoryClient.self] }
        set { self[HistoryClient.self] = newValue }
    }
}

private final class HistoryRuntime: @unchecked Sendable {
    var modelsDirectoryPath: String { Self.modelsDirectoryURL.path }
    var historyDirectoryPath: String { Self.historyDirectoryURL.path }

    func applyRetention(
        _ retentionMode: HistoryRetentionMode,
        to currentDays: [TranscriptHistoryDay]
    ) -> [TranscriptHistoryDay] {
        if !retentionMode.keepsHistory {
            clearPersistedHistoryArtifacts()
            return []
        }
        ensureDataDirectories(retentionMode: retentionMode)
        return pruned(days: currentDays, retentionMode: retentionMode)
    }

    func appendEntry(_ request: AppendEntryRequest) -> [TranscriptHistoryDay] {
        guard request.retentionMode.keepsHistory else { return request.currentDays }

        let day = Self.historyDayFormatter.string(from: request.timestamp)
        let entry = TranscriptHistoryEntry(
            id: request.id,
            timestamp: request.timestamp,
            transcript: request.retentionMode.keepsTranscripts ? request.transcript : "",
            modelID: request.modelID,
            transcriptionMode: request.mode,
            audioDurationSeconds: request.audioDuration,
            transcriptionElapsedSeconds: request.transcriptionElapsed,
            characterCount: request.transcript.count,
            pasteResult: request.pasteResult,
            audioRelativePath: request.audioRelativePath,
            transcriptRelativePath: request.transcriptRelativePath
        )

        var updatedDays = request.currentDays
        if let dayIndex = updatedDays.firstIndex(where: { $0.day == day }) {
            updatedDays[dayIndex].entries.insert(entry, at: 0)
            if updatedDays[dayIndex].entries.count > 200 {
                updatedDays[dayIndex].entries.removeLast(updatedDays[dayIndex].entries.count - 200)
            }
        } else {
            updatedDays.append(TranscriptHistoryDay(day: day, entries: [entry]))
        }
        updatedDays.sort { $0.day > $1.day }
        return updatedDays
    }

    func persistArtifacts(_ request: PersistArtifactsRequest) -> PersistedArtifacts? {
        guard request.retentionMode.keepsHistory else { return nil }
        ensureDataDirectories(retentionMode: request.retentionMode)

        let fileManager = FileManager.default
        let stamp = Self.historyArtifactFormatter.string(from: request.timestamp)
        let safeModelID = request.modelID.replacingOccurrences(of: "/", with: "-")
        let baseName = "\(stamp)-\(safeModelID)-\(request.mode)"

        let audioTarget = Self.historyMediaDirectoryURL.appending(path: "\(baseName).wav")
        let transcriptTarget = Self.historyTranscriptsDirectoryURL.appending(path: "\(baseName).txt")

        var artifacts = PersistedArtifacts()
        do {
            if request.retentionMode.keepsAudio {
                if fileManager.fileExists(atPath: audioTarget.path) {
                    try fileManager.removeItem(at: audioTarget)
                }
                try fileManager.copyItem(at: request.audioURL, to: audioTarget)
                Self.applyProtection(to: audioTarget)
                artifacts.audioRelativePath = "media/\(audioTarget.lastPathComponent)"
            }
            if request.retentionMode.keepsTranscripts {
                if fileManager.fileExists(atPath: transcriptTarget.path) {
                    try fileManager.removeItem(at: transcriptTarget)
                }
                try request.transcript.write(to: transcriptTarget, atomically: true, encoding: .utf8)
                Self.applyProtection(to: transcriptTarget)
                artifacts.transcriptRelativePath = "transcripts/\(transcriptTarget.lastPathComponent)"
            }
            return artifacts
        } catch {
            return nil
        }
    }

    func openHistoryFolder(retentionMode: HistoryRetentionMode) -> Bool {
        guard retentionMode.keepsHistory else { return false }
        if !FileManager.default.fileExists(atPath: Self.historyDirectoryURL.path) {
            ensureDataDirectories(retentionMode: retentionMode)
        }
        NSWorkspace.shared.open(Self.historyDirectoryURL)
        return true
    }

    func historyAudioURL(relativePath: String?) -> URL? {
        guard let relativePath else { return nil }
        let audioURL = Self.historyDirectoryURL.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return nil }
        return audioURL
    }

    private func ensureDataDirectories(retentionMode: HistoryRetentionMode) {
        let fileManager = FileManager.default
        Self.ensureDirectory(Self.modelsDirectoryURL, using: fileManager)
        Self.ensureDirectory(Self.historyDirectoryURL, using: fileManager)
        if retentionMode.keepsAudio {
            Self.ensureDirectory(Self.historyMediaDirectoryURL, using: fileManager)
        } else {
            try? fileManager.removeItem(at: Self.historyMediaDirectoryURL)
        }
        if retentionMode.keepsTranscripts {
            Self.ensureDirectory(Self.historyTranscriptsDirectoryURL, using: fileManager)
        } else {
            try? fileManager.removeItem(at: Self.historyTranscriptsDirectoryURL)
        }
    }

    private func clearPersistedHistoryArtifacts() {
        try? FileManager.default.removeItem(at: Self.historyDirectoryURL)
    }

    private func pruned(
        days: [TranscriptHistoryDay],
        retentionMode: HistoryRetentionMode
    ) -> [TranscriptHistoryDay] {
        var updatedDays = days
        if !retentionMode.keepsAudio {
            for dayIndex in updatedDays.indices {
                for entryIndex in updatedDays[dayIndex].entries.indices {
                    updatedDays[dayIndex].entries[entryIndex].audioRelativePath = nil
                }
            }
        }
        if !retentionMode.keepsTranscripts {
            for dayIndex in updatedDays.indices {
                for entryIndex in updatedDays[dayIndex].entries.indices {
                    updatedDays[dayIndex].entries[entryIndex].transcriptRelativePath = nil
                    updatedDays[dayIndex].entries[entryIndex].transcript = ""
                }
            }
        }
        return updatedDays
    }

    private static let historyDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let historyArtifactFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static var protectedAttributes: [FileAttributeKey: Any] {
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    }

    private static func ensureDirectory(_ url: URL, using fileManager: FileManager) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: protectedAttributes)
        applyProtection(to: url, using: fileManager)
    }

    private static func applyProtection(to url: URL, using fileManager: FileManager = FileManager.default) {
        try? fileManager.setAttributes(protectedAttributes, ofItemAtPath: url.path)
    }

    private static var appDocumentsDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appending(path: "Gloam", directoryHint: .isDirectory)
    }

    private static var modelsDirectoryURL: URL {
        appDocumentsDirectoryURL.appending(path: "models", directoryHint: .isDirectory)
    }

    private static var historyDirectoryURL: URL {
        appDocumentsDirectoryURL.appending(path: "history", directoryHint: .isDirectory)
    }

    private static var historyMediaDirectoryURL: URL {
        historyDirectoryURL.appending(path: "media", directoryHint: .isDirectory)
    }

    private static var historyTranscriptsDirectoryURL: URL {
        historyDirectoryURL.appending(path: "transcripts", directoryHint: .isDirectory)
    }
}
