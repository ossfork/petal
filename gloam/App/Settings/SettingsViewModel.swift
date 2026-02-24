import Dependencies
import HistoryClient
import ModelDownloadFeature
import Observation
import Onboarding
import PermissionsClient
import Shared

@MainActor
@Observable
final class SettingsViewModel {
    @ObservationIgnored @Shared(.trimSilenceEnabled) var trimSilenceEnabled = true
    @ObservationIgnored @Shared(.autoSpeedEnabled) var autoSpeedEnabled = true
    @ObservationIgnored @Shared(.transcriptionMode) var transcriptionMode: TranscriptionMode = .verbatim
    @ObservationIgnored @Shared(.smartPrompt) var smartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said."
    @ObservationIgnored @Shared(.historyRetentionMode) var historyRetentionMode: HistoryRetentionMode = .both
    @ObservationIgnored @Shared(.compressHistoryAudio) var compressHistoryAudio = false
    @ObservationIgnored @Shared(.transcriptHistoryDays) private var transcriptHistoryDays: [TranscriptHistoryDay] = []

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

    var selectedModelOption: ModelOption? {
        modelDownloadViewModel.selectedModelOption
    }

    var historyDirectoryPath: String {
        historyClient.historyDirectoryPath()
    }

    private let modelDownloadViewModel: ModelDownloadModel
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient

    init(appModel: AppModel) {
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

    func historyRetentionModeChanged(_ mode: HistoryRetentionMode) {
        historyRetentionMode = mode
        transcriptHistoryDays = historyClient.applyRetention(mode, transcriptHistoryDays)
    }

    func openHistoryInFinder() {
        _ = historyClient.openHistoryFolder(historyRetentionMode)
    }
}
