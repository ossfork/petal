import Dependencies
import DownloadClient
import HistoryClient
import KeyboardShortcuts
import Observation
import PermissionsClient
import Sauce
import Shared

@MainActor
@Observable
public final class OnboardingModel {
    public enum Page: Int, CaseIterable, Sendable {
        case welcome
        case model
        case shortcut
        case microphone
        case accessibility
        case historyRetention
        case download
    }

    public var selectedModelID: String = ModelOption.defaultOption.rawValue {
        didSet {
            let normalized = ModelOption.from(modelID: selectedModelID).rawValue
            if selectedModelID != normalized {
                selectedModelID = normalized
                return
            }
            $selectedModelIDStorage.withLock { $0 = normalized }
        }
    }

    public var isDownloadingModel = false
    public var downloadProgress = 0.0
    public var downloadStatus = ""
    public var downloadSpeedText: String?
    public var microphonePermissionState: MicrophonePermissionState = .notDetermined
    public var microphoneAuthorized = false
    public var accessibilityAuthorized = false
    public var historyRetentionMode: HistoryRetentionMode = .both {
        didSet {
            $historyRetentionModeStorage.withLock { $0 = historyRetentionMode.rawValue }
        }
    }

    public var lastError: String?
    public var transientMessage: String?

    public var onCompleted: (@MainActor () -> Void)?

    @ObservationIgnored @Dependency(\.downloadClient) private var downloadClient
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    @ObservationIgnored @Dependency(\.continuousClock) private var clock

    @ObservationIgnored @Shared(.selectedModelID) private var selectedModelIDStorage = ModelOption.defaultOption.rawValue
    @ObservationIgnored @Shared(.hasCompletedSetup) private var hasCompletedSetupStorage = false
    @ObservationIgnored @Shared(.historyRetentionMode) private var historyRetentionModeStorage = HistoryRetentionMode.both.rawValue

    @ObservationIgnored private var permissionMonitorTask: Task<Void, Never>?
    @ObservationIgnored private let isPreviewMode: Bool

    public init(isPreviewMode: Bool = false) {
        self.isPreviewMode = isPreviewMode

        if isPreviewMode {
            selectedModelID = ModelOption.defaultOption.rawValue
            historyRetentionMode = .both
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            accessibilityAuthorized = true
            return
        }

        selectedModelID = ModelOption.from(modelID: selectedModelIDStorage).rawValue
        historyRetentionMode = HistoryRetentionMode(rawValue: historyRetentionModeStorage) ?? .both

        let alreadyDownloaded = downloadClient.isModelDownloaded(ModelOption.from(modelID: selectedModelIDStorage))
        downloadProgress = alreadyDownloaded ? 1 : 0
        downloadStatus = alreadyDownloaded ? "Model already downloaded." : ""

        startPermissionMonitoring()
    }

    // MARK: - Computed

    public var selectedModelOption: ModelOption? {
        ModelOption(rawValue: selectedModelID)
    }

    public var isSelectedModelDownloaded: Bool {
        guard let selectedModelOption else { return false }
        return downloadClient.isModelDownloaded(selectedModelOption)
    }

    public var hasConfiguredShortcut: Bool {
        KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil
    }

    public var currentModelSummary: String {
        guard let selectedModelOption else { return "No model selected" }
        return "\(selectedModelOption.displayName) - \(selectedModelOption.sizeLabel)"
    }

    public var modelsDirectoryDisplayPath: String {
        historyClient.modelsDirectoryPath()
    }

    public var downloadSummaryText: String {
        let percent = Int((downloadProgress * 100).rounded())

        if let downloadSpeedText {
            return "\(percent)% - \(downloadSpeedText)"
        }

        return "\(percent)%"
    }

    public var microphonePermissionActionTitle: String {
        switch microphonePermissionState {
        case .notDetermined:
            return "Grant Microphone"
        case .denied:
            return "Open Mic Settings"
        case .authorized:
            return "Microphone Enabled"
        }
    }

    // MARK: - Actions

    public func windowAppeared() {
        if isPreviewMode { return }
        refreshPermissionStatus()
    }

    public func selectedModelChanged() {
        transientMessage = nil
        lastError = nil
    }

    public func microphonePermissionButtonTapped() async {
        if isPreviewMode {
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            lastError = nil
            return
        }

        let granted = await permissionsClient.requestMicrophonePermission()
        await refreshPermissionStatusAsync()

        if granted || microphoneAuthorized {
            lastError = nil
            return
        }

        if microphonePermissionState == .denied {
            await permissionsClient.openMicrophonePrivacySettings()
            lastError = "Enable microphone access in System Settings, then return to Gloam."
            return
        }

        lastError = "Microphone access is required to record audio."
    }

    public func accessibilityPermissionButtonTapped() {
        if isPreviewMode {
            accessibilityAuthorized = true
            transientMessage = nil
            return
        }

        Task {
            await ensureAccessibilityPermission()
        }
    }

    public func downloadModel() async {
        guard let option = selectedModelOption else {
            lastError = "Please select a valid model."
            return
        }

        guard !isDownloadingModel else { return }

        isDownloadingModel = true
        downloadProgress = 0
        downloadStatus = "Preparing download..."
        downloadSpeedText = nil
        transientMessage = nil
        lastError = nil

        do {
            try await downloadClient.downloadModel(option) { update in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.downloadProgress = min(max(update.fractionCompleted, 0), 1)
                    self.downloadStatus = update.status
                    self.downloadSpeedText = update.speedText
                }
            }

            isDownloadingModel = false
            downloadProgress = 1
            downloadSpeedText = nil
            downloadStatus = "Download complete!"
            transientMessage = "Model downloaded. Click Finish Setup."
            lastError = nil
        } catch {
            isDownloadingModel = false
            downloadSpeedText = nil
            lastError = error.localizedDescription
        }
    }

    public func completeSetup() {
        $hasCompletedSetupStorage.withLock { $0 = true }
        permissionMonitorTask?.cancel()
        onCompleted?()
    }

    // MARK: - Private

    private func ensureAccessibilityPermission() async {
        if isPreviewMode {
            accessibilityAuthorized = true
            transientMessage = nil
            lastError = nil
            return
        }

        await permissionsClient.promptForAccessibilityPermission()
        await refreshPermissionStatusAsync()

        if accessibilityAuthorized {
            lastError = nil
            transientMessage = nil
            return
        }

        await permissionsClient.openAccessibilityPrivacySettings()
        lastError = "Accessibility permission is required to finish setup."
        transientMessage = "Enable Accessibility in System Settings, then return to Gloam."
    }

    private func refreshPermissionStatus() {
        if isPreviewMode { return }
        Task { await refreshPermissionStatusAsync() }
    }

    private func refreshPermissionStatusAsync() async {
        if isPreviewMode { return }
        microphonePermissionState = await permissionsClient.microphonePermissionState()
        microphoneAuthorized = microphonePermissionState == .authorized
        accessibilityAuthorized = await permissionsClient.hasAccessibilityPermission()
    }

    private func startPermissionMonitoring() {
        permissionMonitorTask?.cancel()
        permissionMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshPermissionStatusAsync()
                try? await self.clock.sleep(for: .seconds(1))
            }
        }
    }

    deinit {
        permissionMonitorTask?.cancel()
    }
}

// MARK: - Preview Support

#if DEBUG
extension OnboardingModel {
    public static func makePreview(
        configure: (OnboardingModel) -> Void = { _ in }
    ) -> OnboardingModel {
        let model = OnboardingModel(isPreviewMode: true)
        configure(model)
        return model
    }
}
#endif
