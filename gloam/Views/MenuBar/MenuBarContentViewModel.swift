import AppKit
import Observation
import Shared
import SwiftUI

@MainActor
@Observable
final class MenuBarContentViewModel {
    struct HistoryMenuItem: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
    }

    private let appModel: AppModel
    private var updatesModel: CheckForUpdatesModel?

    init(appModel: AppModel, updatesModel: CheckForUpdatesModel? = nil) {
        self.appModel = appModel
        self.updatesModel = updatesModel
    }

    var statusTitle: String { appModel.statusTitle }
    var statusSymbolName: String { appModel.menuBarSymbolName }
    var statusColor: Color {
        switch appModel.sessionState {
        case .recording:
            return .red
        case .processing(.trimming):
            return .orange
        case .processing(.speeding):
            return .teal
        case .processing(.transcribing), .idle, .error:
            return .primary
        }
    }

    var statusErrorMessage: String? {
        guard case let .error(message) = appModel.sessionState else { return nil }
        return message
    }

    var transientMessage: String? { appModel.transientMessage }

    var shouldShowPermissionsSection: Bool {
        !appModel.microphoneAuthorized || !appModel.accessibilityAuthorized
    }

    var needsMicrophonePermission: Bool { !appModel.microphoneAuthorized }
    var needsAccessibilityPermission: Bool { !appModel.accessibilityAuthorized }

    var shouldShowHistoryMenu: Bool {
        appModel.historyRetentionMode.keepsHistory
    }

    var historyMenuItems: [HistoryMenuItem] {
        appModel.recentTranscriptHistoryEntries.map { entry in
            let normalizedTranscript: String = {
                entry.transcript
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }()

            let title: String = {
                guard !normalizedTranscript.isEmpty else { return "Transcript not retained" }
                return String(normalizedTranscript.prefix(56))
            }()

            let subtitle = "\(entry.transcriptionMode.capitalized) • \(entry.characterCount) chars"

            return HistoryMenuItem(
                id: entry.id,
                title: title,
                subtitle: subtitle
            )
        }
    }

    var showsCheckForUpdates: Bool { updatesModel != nil }
    var canCheckForUpdates: Bool { updatesModel?.canCheckForUpdates == true }

    func setUpdatesModel(_ updatesModel: CheckForUpdatesModel?) {
        self.updatesModel = updatesModel
    }

    func requestMicrophonePermission() {
        Task { await appModel.microphonePermissionButtonTapped() }
    }

    func requestAccessibilityPermission() {
        appModel.accessibilityPermissionButtonTapped()
    }

    func copyHistoryEntry(_ entryID: UUID) {
        appModel.copyTranscriptHistoryButtonTapped(entryID)
    }

    func checkForUpdates() {
        updatesModel?.checkForUpdates()
    }

    func openSettings() {
        appModel.openSettingsWindow()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
