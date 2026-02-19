import AppKit
import Foundation

@MainActor
final class HistoryStoreService {
    struct PersistedArtifacts: Sendable {
        var audioRelativePath: String?
        var transcriptRelativePath: String?
    }

    var modelsDirectoryPath: String {
        Self.modelsDirectoryURL.path
    }

    var historyDirectoryPath: String {
        Self.historyDirectoryURL.path
    }

    func bootstrap(
        retentionMode: HistoryRetentionMode,
        storedDays: [TranscriptHistoryDay]
    ) -> [TranscriptHistoryDay] {
        applyRetention(retentionMode, to: storedDays)
    }

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

    func appendEntry(
        currentDays: [TranscriptHistoryDay],
        transcript: String,
        modelID: String,
        mode: String,
        audioDuration: Double,
        transcriptionElapsed: Double,
        pasteResult: PasteResult,
        audioRelativePath: String?,
        transcriptRelativePath: String?,
        retentionMode: HistoryRetentionMode,
        timestamp: Date,
        id: UUID
    ) -> [TranscriptHistoryDay] {
        guard retentionMode.keepsHistory else { return currentDays }

        let day = Self.historyDayFormatter.string(from: timestamp)
        let entry = TranscriptHistoryEntry(
            id: id,
            timestamp: timestamp,
            transcript: retentionMode.keepsTranscripts ? transcript : "",
            modelID: modelID,
            transcriptionMode: mode,
            audioDurationSeconds: audioDuration,
            transcriptionElapsedSeconds: transcriptionElapsed,
            characterCount: transcript.count,
            pasteResult: pasteResult.rawValue,
            audioRelativePath: audioRelativePath,
            transcriptRelativePath: transcriptRelativePath
        )

        var updatedDays = currentDays

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

    func persistArtifacts(
        audioURL: URL,
        transcript: String,
        timestamp: Date,
        mode: String,
        modelID: String,
        retentionMode: HistoryRetentionMode
    ) -> PersistedArtifacts? {
        guard retentionMode.keepsHistory else { return nil }
        ensureDataDirectories(retentionMode: retentionMode)

        let fileManager = FileManager.default
        let stamp = Self.historyArtifactFormatter.string(from: timestamp)
        let safeModelID = modelID.replacingOccurrences(of: "/", with: "-")
        let baseName = "\(stamp)-\(safeModelID)-\(mode)"

        let audioTarget = Self.historyMediaDirectoryURL.appending(path: "\(baseName).wav")
        let transcriptTarget = Self.historyTranscriptsDirectoryURL.appending(path: "\(baseName).txt")

        var artifacts = PersistedArtifacts()

        do {
            if retentionMode.keepsAudio {
                if fileManager.fileExists(atPath: audioTarget.path) {
                    try fileManager.removeItem(at: audioTarget)
                }

                try fileManager.copyItem(at: audioURL, to: audioTarget)
                Self.applyProtection(to: audioTarget)
                artifacts.audioRelativePath = "media/\(audioTarget.lastPathComponent)"
            }

            if retentionMode.keepsTranscripts {
                if fileManager.fileExists(atPath: transcriptTarget.path) {
                    try fileManager.removeItem(at: transcriptTarget)
                }

                try transcript.write(to: transcriptTarget, atomically: true, encoding: .utf8)
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
            .appending(path: "MacX", directoryHint: .isDirectory)
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
