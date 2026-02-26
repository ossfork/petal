import AppKit
import Dependencies
import HistoryClient
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
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient

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
        case .processing(.transcribing), .processing(.refining), .idle, .error:
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
        appModel.recentTranscriptHistoryEntries
            .compactMap { entry in
                guard let transcript = historyClient.transcriptText(entry.preferredTranscriptRelativePath) else { return nil }
                let normalizedTranscript = transcript
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedTranscript.isEmpty else { return nil }

                let title = String(normalizedTranscript.prefix(56))
                let subtitle = "\(entry.modeSummary.capitalized) • \(entry.preferredCharacterCount) chars"

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

    func showAbout() {
        NSApp.sendAction(#selector(AppDelegate.showAboutPanel), to: nil, from: nil)
    }

    func openSettings() {
        appModel.openSettingsWindow()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
