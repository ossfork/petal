import AppKit
import Foundation
import Observation
import Onboarding
import Sparkle
import Shared

@MainActor
@Observable
final class SettingsViewModel {
    enum Section: String, CaseIterable, Hashable, Identifiable {
        case general
        case model
        case shortcut
        case transcription
        case permissions
        case history
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                "General"
            case .model:
                "Model"
            case .shortcut:
                "Shortcut"
            case .transcription:
                "Transcription"
            case .permissions:
                "Permissions"
            case .history:
                "History"
            case .about:
                "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general:
                "gearshape.fill"
            case .model:
                "cpu.fill"
            case .shortcut:
                "keyboard.fill"
            case .transcription:
                "waveform"
            case .permissions:
                "lock.shield.fill"
            case .history:
                "clock.arrow.circlepath"
            case .about:
                "info.circle.fill"
            }
        }
    }

    struct SidebarGroup: Identifiable {
        let id: String
        let title: String?
        let items: [Section]
    }

    let appModel: AppModel
    var selectedSection: Section

    let sidebarGroups: [SidebarGroup] = [
        SidebarGroup(id: "primary", title: nil, items: [.general, .model, .shortcut, .transcription]),
        SidebarGroup(id: "privacy", title: "Privacy & Data", items: [.permissions, .history]),
        SidebarGroup(id: "about", title: "Gloam", items: [.about]),
    ]

    init(appModel: AppModel, selectedSection: Section = .general) {
        self.appModel = appModel
        self.selectedSection = selectedSection
    }

    var settingsMessage: String? {
        appModel.lastError ?? appModel.transientMessage
    }

    var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var recentEntries: [TranscriptHistoryEntry] {
        Array(appModel.recentTranscriptHistoryEntries.prefix(10))
    }

    var modelDownloadViewModel: ModelDownloadViewModel {
        appModel.modelDownloadViewModel
    }

    func requestMicrophonePermission() {
        Task { await appModel.microphonePermissionButtonTapped() }
    }

    func requestAccessibilityPermission() {
        appModel.accessibilityPermissionButtonTapped()
    }

    func openSetupAssistant() {
        appModel.changeModelButtonTapped()
    }

    func selectModel(_ modelID: String) {
        modelDownloadViewModel.selectedModelID = modelID
        modelDownloadViewModel.selectedModelChanged()
    }

    func downloadModel() {
        Task { await modelDownloadViewModel.downloadModel() }
    }

    func openHistoryFolder() {
        appModel.openHistoryFolderButtonTapped()
    }

    func copyHistoryEntry(_ entry: TranscriptHistoryEntry) {
        appModel.copyTranscriptHistoryButtonTapped(entry.id)
    }

    func playHistoryAudio(_ entry: TranscriptHistoryEntry) {
        appModel.playHistoryAudioButtonTapped(entry.id)
    }

    func checkForUpdates() {
        (NSApp.delegate as? AppDelegate)?.updaterController.updater.checkForUpdates()
    }
}

extension SettingsViewModel {
    static func makePreview(_ configure: (AppModel) -> Void = { _ in }) -> SettingsViewModel {
        SettingsViewModel(appModel: AppModel.makePreview(configure))
    }
}
