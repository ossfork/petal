import AppKit
import Foundation
import Observation
import Onboarding
import Sparkle
import Shared
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    var settingsMessage: String? {
        appModel.lastError ?? appModel.transientMessage
    }

    var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (\(build))"
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
        appModel.selectedModelID = modelID
    }

    func downloadModel() {
        Task { await modelDownloadViewModel.downloadModel() }
    }

    func openHistoryFolder() {
        appModel.openHistoryFolderButtonTapped()
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
