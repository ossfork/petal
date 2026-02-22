import Dependencies
import Foundation
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

    // MARK: - Navigation

    public var currentPage: Page

    public let pageOrder: [Page] = [
        .welcome,
        .model,
        .shortcut,
        .microphone,
        .accessibility,
        .historyRetention,
        .download,
    ]

    public var nextPage: Page? {
        guard let currentIndex = pageOrder.firstIndex(of: currentPage),
              pageOrder.indices.contains(currentIndex + 1)
        else { return nil }
        return pageOrder[currentIndex + 1]
    }

    public var previousPage: Page? {
        guard let currentIndex = pageOrder.firstIndex(of: currentPage),
              pageOrder.indices.contains(currentIndex - 1)
        else { return nil }
        return pageOrder[currentIndex - 1]
    }

    public func moveForward() {
        guard let nextPage else { return }
        currentPage = nextPage
    }

    public func moveBack() {
        guard let previousPage else { return }
        currentPage = previousPage
    }

    // MARK: - Page Container

    public var showBack: Bool {
        guard previousPage != nil else { return false }
        if currentPage == .download, modelDownloadViewModel.isDownloadingModel { return false }
        return true
    }

    public var currentPrimaryTitle: String {
        switch currentPage {
        case .accessibility:
            return accessibilityAuthorized ? "Continue" : "Enable Accessibility"
        case .microphone:
            return microphoneAuthorized ? "Continue" : "Enable Microphone"
        case .download:
            if modelDownloadViewModel.isDownloadingModel { return "Downloading..." }
            if modelDownloadViewModel.isSelectedModelDownloaded { return "Finish Setup" }
            return currentPage.primaryTitle
        default:
            return currentPage.primaryTitle
        }
    }

    public var primaryDisabled: Bool {
        switch currentPage {
        case .welcome, .historyRetention: false
        case .model: selectedModelOption == nil
        case .shortcut: !hasConfiguredShortcut
        case .microphone: false
        case .accessibility: false
        case .download: modelDownloadViewModel.isDownloadingModel
        }
    }

    public func primaryActionTapped() {
        switch currentPage {
        case .model:
            guard selectedModelOption != nil else { return }
            moveForward()
        case .shortcut:
            guard hasConfiguredShortcut else { return }
            moveForward()
        case .download:
            if modelDownloadViewModel.isSelectedModelDownloaded {
                completeSetup()
            } else {
                Task { await downloadModel() }
            }
        case .microphone:
            if microphoneAuthorized {
                moveForward()
            } else {
                Task { await microphonePermissionButtonTapped() }
            }
        case .accessibility:
            if accessibilityAuthorized {
                moveForward()
            } else {
                accessibilityPermissionButtonTapped()
            }
        default:
            moveForward()
        }
    }

    // MARK: - Model Download

    public let modelDownloadViewModel: ModelDownloadViewModel

    public var selectedModelID: String {
        get { modelDownloadViewModel.selectedModelID }
        set { modelDownloadViewModel.selectedModelID = newValue }
    }

    public var isDownloadingModel: Bool {
        get { modelDownloadViewModel.isDownloadingModel }
        set { modelDownloadViewModel.isDownloadingModel = newValue }
    }

    public var downloadProgress: Double {
        get { modelDownloadViewModel.downloadProgress }
        set { modelDownloadViewModel.downloadProgress = newValue }
    }

    public var downloadStatus: String {
        get { modelDownloadViewModel.downloadStatus }
        set { modelDownloadViewModel.downloadStatus = newValue }
    }

    public var downloadSpeedText: String? {
        get { modelDownloadViewModel.downloadSpeedText }
        set { modelDownloadViewModel.downloadSpeedText = newValue }
    }

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

    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.continuousClock) private var clock

    @ObservationIgnored @Shared(.hasCompletedSetup) private var hasCompletedSetupStorage = false
    @ObservationIgnored @Shared(.historyRetentionMode) private var historyRetentionModeStorage = HistoryRetentionMode.both.rawValue

    @ObservationIgnored private var permissionMonitorTask: Task<Void, Never>?
    @ObservationIgnored private let isPreviewMode: Bool

    public init(initialPage: Page = .welcome, downloadViewModel: ModelDownloadViewModel? = nil, isPreviewMode: Bool = false) {
        self.currentPage = initialPage
        self.isPreviewMode = isPreviewMode
        modelDownloadViewModel = downloadViewModel ?? ModelDownloadViewModel(isPreviewMode: isPreviewMode)

        if isPreviewMode {
            historyRetentionMode = .both
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            accessibilityAuthorized = true
            return
        }

        historyRetentionMode = HistoryRetentionMode(rawValue: historyRetentionModeStorage) ?? .both

        startPermissionMonitoring()
    }

    // MARK: - Computed

    public var selectedModelOption: ModelOption? {
        modelDownloadViewModel.selectedModelOption
    }

    public var hasConfiguredShortcut: Bool {
        KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil
    }

    public var microphonePermissionActionTitle: String {
        switch microphonePermissionState {
        case .notDetermined:
            return "Allow Microphone"
        case .denied:
            return "Open Microphone Settings"
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
        modelDownloadViewModel.selectedModelChanged()
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
            lastError = "Turn on microphone access in System Settings, then return to Gloam."
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
        await modelDownloadViewModel.downloadModel()
        transientMessage = modelDownloadViewModel.transientMessage
        lastError = modelDownloadViewModel.lastError
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
        lastError = "Accessibility access is required to continue."
        transientMessage = "Turn on Accessibility in System Settings, then return to Gloam."
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

// MARK: - Page Metadata

extension OnboardingModel.Page {
    public var primaryTitle: String {
        switch self {
        case .welcome, .model, .shortcut, .microphone, .accessibility, .historyRetention: "Continue"
        case .download: "Download Model"
        }
    }

    public var primaryActionDelay: CGFloat {
        switch self {
        case .welcome: 1.5
        default: 0.1
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension OnboardingModel {
    public static func makePreview(
        page: Page = .welcome,
        configure: (OnboardingModel) -> Void = { _ in }
    ) -> OnboardingModel {
        let model = OnboardingModel(initialPage: page, isPreviewMode: true)
        configure(model)
        return model
    }
}
#endif
