import Dependencies
import HistoryClient
import Observation
import Onboarding
import PermissionsClient
import Shared

@MainActor
@Observable
final class SettingsViewModel {
    var microphoneAuthorized = false
    var accessibilityAuthorized = false
    var permissionMessage: String?

    var selectedModelID: String {
        get { modelDownloadViewModel.selectedModelID }
        set {
            modelDownloadViewModel.selectedModelID = newValue
            modelDownloadViewModel.selectedModelChanged()
        }
    }

    var isSelectedModelDownloaded: Bool {
        modelDownloadViewModel.isSelectedModelDownloaded
    }

    var isDownloadingModel: Bool {
        modelDownloadViewModel.isDownloadingModel
    }

    var isPaused: Bool {
        modelDownloadViewModel.isPaused
    }

    var downloadProgress: Double {
        modelDownloadViewModel.downloadProgress
    }

    var downloadStatus: String {
        modelDownloadViewModel.downloadStatus
    }

    var downloadSummaryText: String {
        modelDownloadViewModel.downloadSummaryText
    }

    var downloadError: String? {
        modelDownloadViewModel.lastError
    }

    var trimSilenceEnabled: Bool {
        get { appModel.trimSilenceEnabled }
        set { appModel.trimSilenceEnabled = newValue }
    }

    var autoSpeedEnabled: Bool {
        get { appModel.autoSpeedEnabled }
        set { appModel.autoSpeedEnabled = newValue }
    }

    var transcriptionMode: TranscriptionMode {
        get { appModel.transcriptionMode }
        set { appModel.transcriptionMode = newValue }
    }

    var smartPrompt: String {
        get { appModel.smartPrompt }
        set { appModel.smartPrompt = newValue }
    }

    var historyRetentionMode: HistoryRetentionMode {
        get { appModel.historyRetentionMode }
        set { appModel.historyRetentionModeChanged(newValue) }
    }

    var compressHistoryAudio: Bool {
        get { appModel.compressHistoryAudio }
        set { appModel.compressHistoryAudio = newValue }
    }

    var selectedModelOption: ModelOption? {
        modelDownloadViewModel.selectedModelOption
    }

    var historyDirectoryPath: String {
        historyClient.historyDirectoryPath()
    }

    private let appModel: AppModel
    private let modelDownloadViewModel: ModelDownloadViewModel
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient

    init(appModel: AppModel) {
        self.appModel = appModel
        self.modelDownloadViewModel = appModel.modelDownloadViewModel
    }

    func refreshPermissions() async {
        microphoneAuthorized = await permissionsClient.microphonePermissionState() == .authorized
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
    }

    func grantMicrophonePermissionButtonTapped() async {
        let granted = await permissionsClient.requestMicrophonePermission()
        microphoneAuthorized = granted
        if !granted {
            permissionMessage = "Open System Settings to grant microphone access."
            await permissionsClient.openMicrophonePrivacySettings()
        }
    }

    func grantAccessibilityPermissionButtonTapped() async {
        await permissionsClient.promptForAccessibilityPermission()
        try? await Task.sleep(for: .milliseconds(500))
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
        if !accessibilityAuthorized {
            permissionMessage = "Open System Settings to grant accessibility access."
        }
    }

    func downloadButtonTapped() async {
        await modelDownloadViewModel.downloadButtonTapped()
    }

    func pauseButtonTapped() {
        modelDownloadViewModel.pauseButtonTapped()
    }

    func resumeButtonTapped() async {
        await modelDownloadViewModel.resumeButtonTapped()
    }

    func cancelButtonTapped() {
        modelDownloadViewModel.cancelButtonTapped()
    }

    func openHistoryInFinder() {
        _ = historyClient.openHistoryFolder(historyRetentionMode)
    }
}
