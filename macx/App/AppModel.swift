import AppKit
import Dependencies
import Foundation
import IssueReporting
import KeyboardShortcuts
import Observation
import os
import Sauce
import Sharing
import UserNotifications

@MainActor
@Observable
final class AppModel {
    enum SessionState: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    enum SetupStep: Int, CaseIterable, Sendable {
        case model
        case shortcut
        case download
    }

    @ObservationIgnored @Shared(.hasCompletedSetup) private var hasCompletedSetupStorage = false
    @ObservationIgnored @Shared(.selectedModelID) private var selectedModelIDStorage = ModelOption.defaultOption.rawValue
    @ObservationIgnored @Shared(.transcriptionMode) private var transcriptionModeStorage = TranscriptionMode.verbatim.rawValue
    @ObservationIgnored @Shared(.smartPrompt) private var smartPromptStorage = "Clean up filler words and repeated phrases. Return a polished version of what was said."

    var hasCompletedSetup = false {
        didSet {
            $hasCompletedSetupStorage.withLock { $0 = hasCompletedSetup }
        }
    }

    var selectedModelID = ModelOption.defaultOption.rawValue {
        didSet {
            let normalized = ModelOption.from(modelID: selectedModelID).rawValue
            if selectedModelID != normalized {
                selectedModelID = normalized
                return
            }
            $selectedModelIDStorage.withLock { $0 = normalized }
        }
    }

    var transcriptionMode: TranscriptionMode = .verbatim {
        didSet {
            $transcriptionModeStorage.withLock { $0 = transcriptionMode.rawValue }
        }
    }

    var smartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said." {
        didSet {
            $smartPromptStorage.withLock { $0 = smartPrompt }
        }
    }

    var setupStep: SetupStep = .model
    var isDownloadingModel = false
    var downloadProgress = 0.0
    var downloadStatus = ""
    var downloadSpeedText: String?
    var sessionState: SessionState = .idle
    var lastError: String?
    var transientMessage: String?
    var microphonePermissionState: MicrophonePermissionState = .notDetermined
    var microphoneAuthorized = false
    var accessibilityAuthorized = false

    @ObservationIgnored @Dependency(\.continuousClock) private var clock
    @ObservationIgnored private let logger = Logger(subsystem: "com.optimalapps.macx", category: "AppModel")

    @ObservationIgnored private let permissionsService: PermissionsService
    @ObservationIgnored private let modelSetupService: ModelSetupService
    @ObservationIgnored private let audioCaptureService: AudioCaptureService
    @ObservationIgnored private let transcriptionService: TranscriptionService
    @ObservationIgnored private let pasteService: PasteService
    @ObservationIgnored private let keyboardMonitorService: KeyboardMonitorService
    @ObservationIgnored private let floatingCapsuleController: FloatingCapsuleController
    @ObservationIgnored private let isPreviewMode: Bool

    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var pushToTalkIsActive = false
    @ObservationIgnored private var toggleRecordingIsActive = false
    @ObservationIgnored private var isAwaitingCancelRecordingConfirmation = false
    @ObservationIgnored private var ignoreNextShortcutKeyUp = false
    @ObservationIgnored private var currentShortcutPressStart: Date?
    @ObservationIgnored private var setupWindowController: SetupWindowController?
    @ObservationIgnored private var didAutoPromptAccessibilityInSetup = false
    @ObservationIgnored private var transcriptionProgressTask: Task<Void, Never>?
    @ObservationIgnored private var estimatedTranscriptionRTF = 2.2
    @ObservationIgnored private let toggleActivationThresholdSeconds = 2.0

    nonisolated private static var isRunningInSwiftUIPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    init(isPreviewMode: Bool = AppModel.isRunningInSwiftUIPreview) {
        permissionsService = PermissionsService()
        modelSetupService = ModelSetupService()
        audioCaptureService = AudioCaptureService()
        transcriptionService = TranscriptionService()
        pasteService = PasteService()
        keyboardMonitorService = KeyboardMonitorService()
        floatingCapsuleController = FloatingCapsuleController()
        self.isPreviewMode = isPreviewMode

        if isPreviewMode {
            hasCompletedSetup = true
            selectedModelID = ModelOption.defaultOption.rawValue
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            accessibilityAuthorized = true
            return
        }

        hasCompletedSetup = hasCompletedSetupStorage
        selectedModelID = ModelOption.from(modelID: selectedModelIDStorage).rawValue
        transcriptionMode = TranscriptionMode(rawValue: transcriptionModeStorage) ?? .verbatim
        smartPrompt = smartPromptStorage

        registerShortcutHandlers()
        registerKeyboardMonitor()
        refreshPermissionStatus()
        logger.info("AppModel initialized. setupCompleted=\(self.hasCompletedSetup, privacy: .public), model=\(self.selectedModelID, privacy: .public)")
        consoleLog("AppModel initialized. setupCompleted=\(self.hasCompletedSetup), model=\(self.selectedModelID)")

        Task { await appDidLaunch() }
    }

    var selectedModelOption: ModelOption? {
        ModelOption(rawValue: selectedModelID)
    }

    var isSelectedModelDownloaded: Bool {
        guard let selectedModelOption else { return false }
        return modelSetupService.isModelDownloaded(selectedModelOption)
    }

    var statusTitle: String {
        switch sessionState {
        case .idle:
            return hasCompletedSetup ? "Ready" : "Setup Required"
        case .recording:
            return "REC"
        case .transcribing:
            return "Transcribing"
        case .error:
            return "Error"
        }
    }

    var menuBarSymbolName: String {
        switch sessionState {
        case .idle:
            return "waveform.badge.mic"
        case .recording:
            return "record.circle.fill"
        case .transcribing:
            return "hourglass"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var currentModelSummary: String {
        guard let selectedModelOption else {
            return "No model selected"
        }

        return "\(selectedModelOption.displayName) - \(selectedModelOption.sizeLabel)"
    }

    var shortcutDisplayText: String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .pushToTalk) else {
            return "No shortcut set"
        }

        let modifiers = shortcut.modifiers.ks_symbolicRepresentation
        let key = Sauce.shared.key(for: shortcut.carbonKeyCode)?.rawValue.uppercased() ?? "?"
        return "Current: \(modifiers)\(key)"
    }

    var shortcutUsageText: String {
        "Tap and release quickly to toggle recording. Hold for at least \(Int(toggleActivationThresholdSeconds)) seconds for push-to-talk."
    }

    var setupStepItems: [SetupStep] {
        SetupStep.allCases
    }

    var setupPrimaryButtonTitle: String {
        switch setupStep {
        case .model:
            return "Continue"
        case .shortcut:
            return "Continue"
        case .download:
            if isDownloadingModel {
                return "Downloading..."
            }

            if !microphoneAuthorized {
                switch microphonePermissionState {
                case .authorized:
                    break
                case .notDetermined:
                    return "Grant Microphone"
                case .denied:
                    return "Open Mic Settings"
                }
            }

            if isSelectedModelDownloaded {
                return "Finish Setup"
            }

            return "Download Model"
        }
    }

    var setupPrimaryButtonDisabled: Bool {
        isDownloadingModel
    }

    var setupCanGoBack: Bool {
        setupStep != .model && !isDownloadingModel
    }

    var setupStepTitle: String {
        switch setupStep {
        case .model:
            return "Choose Model"
        case .shortcut:
            return "Choose Shortcut"
        case .download:
            return "Download & Permissions"
        }
    }

    var setupStepDescription: String {
        switch setupStep {
        case .model:
            return "Pick a Voxtral Mini model. You can change this later from the menu bar."
        case .shortcut:
            return "Set a shortcut. Quick tap toggles recording; holding for at least 2 seconds uses press-to-talk."
        case .download:
            return "Allow permissions and download your selected model."
        }
    }

    var setupDownloadSummaryText: String {
        let percent = Int((downloadProgress * 100).rounded())

        if let downloadSpeedText {
            return "\(percent)% - \(downloadSpeedText)"
        }

        return "\(percent)%"
    }

    func setupStepDisplayName(_ step: SetupStep) -> String {
        switch step {
        case .model:
            return "Model"
        case .shortcut:
            return "Shortcut"
        case .download:
            return "Download"
        }
    }

    func appDidLaunch() async {
        if isPreviewMode { return }
        guard !didBootstrap else { return }
        didBootstrap = true
        logger.info("App did launch. setupCompleted=\(self.hasCompletedSetup, privacy: .public), modelDownloaded=\(self.isSelectedModelDownloaded, privacy: .public)")
        consoleLog("App did launch. setupCompleted=\(self.hasCompletedSetup), modelDownloaded=\(self.isSelectedModelDownloaded)")

        if hasCompletedSetup, isSelectedModelDownloaded {
            Task { await warmModelTask() }
            return
        }

        hasCompletedSetup = false
        beginSetupFlow()
        try? await clock.sleep(for: .milliseconds(150))
        showSetupWindow()
    }

    func setupWindowAppeared() {
        if isPreviewMode { return }
        refreshPermissionStatus()
    }

    func changeModelButtonTapped() {
        if isPreviewMode {
            beginSetupFlow()
            return
        }
        beginSetupFlow()
        showSetupWindow()
    }

    func selectedModelSelectionChanged() {
        transientMessage = nil
        lastError = nil
    }

    func closeSetupWindowButtonTapped() {
        if isPreviewMode { return }
        setupWindowController?.close()
    }

    func setupBackButtonTapped() {
        guard setupCanGoBack else { return }

        switch setupStep {
        case .model:
            break
        case .shortcut:
            setupStep = .model
        case .download:
            setupStep = .shortcut
        }

        lastError = nil
    }

    func setupPrimaryButtonTapped() async {
        logger.info("Setup primary button tapped at step=\(self.setupStepTitle, privacy: .public)")
        consoleLog("Setup primary button tapped at step=\(self.setupStepTitle)")
        switch setupStep {
        case .model:
            guard selectedModelOption != nil else {
                lastError = "Please select a valid model."
                return
            }

            setupStep = .shortcut
            lastError = nil
        case .shortcut:
            guard hasConfiguredShortcut else {
                lastError = "Set a push-to-talk shortcut before continuing."
                return
            }

            setupStep = .download
            lastError = nil
            await requestPermissionsForSetupIfNeeded()
        case .download:
            await setupDownloadPrimaryButtonTapped()
        }
    }

    func downloadModelButtonTapped() async {
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
        logger.info("Starting model download: \(option.rawValue, privacy: .public)")
        consoleLog("Starting model download: \(option.rawValue)")

        do {
            try await modelSetupService.downloadModel(option) { update in
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
            logger.info("Model download completed: \(option.rawValue, privacy: .public)")
            consoleLog("Model download completed: \(option.rawValue)")
        } catch {
            isDownloadingModel = false
            downloadSpeedText = nil
            lastError = error.localizedDescription
            reportIssue(error)
            logger.error("Model download failed: \(error.localizedDescription, privacy: .public)")
            consoleLog("Model download failed: \(error.localizedDescription)")
        }
    }

    func microphonePermissionButtonTapped() async {
        if isPreviewMode {
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            lastError = nil
            return
        }

        let granted = await permissionsService.requestMicrophonePermission()
        refreshPermissionStatus()
        logger.info("Microphone permission request resolved. granted=\(granted, privacy: .public), authorized=\(self.microphoneAuthorized, privacy: .public)")
        consoleLog("Microphone permission request resolved. granted=\(granted), authorized=\(self.microphoneAuthorized)")

        if granted || microphoneAuthorized {
            lastError = nil
            return
        }

        if microphonePermissionState == .denied {
            permissionsService.openMicrophonePrivacySettings()
            lastError = "Enable microphone access in System Settings, then return to MacX."
            return
        }

        lastError = "Microphone access is required to record audio."
    }

    func accessibilityPermissionButtonTapped() {
        if isPreviewMode {
            accessibilityAuthorized = true
            transientMessage = nil
            return
        }

        permissionsService.promptForAccessibilityPermission()
        refreshPermissionStatus()
        logger.info("Accessibility permission prompt shown. authorized=\(self.accessibilityAuthorized, privacy: .public)")
        consoleLog("Accessibility permission prompt shown. authorized=\(self.accessibilityAuthorized)")

        if !accessibilityAuthorized {
            permissionsService.openAccessibilityPrivacySettings()
            transientMessage = "Enable Accessibility to allow automatic paste."
        }
    }

    func pushToTalkKeyDown() async {
        logger.info("Push-to-talk key down")
        consoleLog("Push-to-talk key down")

        if isAwaitingCancelRecordingConfirmation {
            dismissCancelRecordingConfirmation()
        }

        guard hasCompletedSetup else {
            transientMessage = "Complete setup before recording."
            beginSetupFlow()
            showSetupWindow()
            return
        }

        if toggleRecordingIsActive, !audioCaptureService.isRecording {
            toggleRecordingIsActive = false
        }

        if toggleRecordingIsActive, audioCaptureService.isRecording {
            toggleRecordingIsActive = false
            ignoreNextShortcutKeyUp = true
            logger.info("Toggle recording stop requested")
            consoleLog("Toggle recording stop requested")
            await stopRecordingAndTranscribe()
            return
        }

        guard !pushToTalkIsActive else {
            return
        }

        pushToTalkIsActive = true
        currentShortcutPressStart = Date()

        if !microphoneAuthorized {
            await microphonePermissionButtonTapped()
            refreshPermissionStatus()

            guard microphoneAuthorized else {
                sessionState = .error("Microphone permission denied")
                transientMessage = "Enable microphone access to record."
                pushToTalkIsActive = false
                currentShortcutPressStart = nil
                floatingCapsuleController.showError("Microphone denied")
                await hideCapsuleAfterDelay()
                return
            }
        }

        do {
            try audioCaptureService.startRecording { [weak self] level in
                guard let self else { return }
                Task { @MainActor [self, level] in
                    self.recordingLevelDidUpdate(level)
                }
            }

            isAwaitingCancelRecordingConfirmation = false
            sessionState = .recording
            floatingCapsuleController.showRecording()
            logger.info("Recording started")
            consoleLog("Recording started")
        } catch {
            reportIssue(error)
            sessionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
            pushToTalkIsActive = false
            currentShortcutPressStart = nil
            floatingCapsuleController.showError("Recording failed")
            logger.error("Recording failed to start: \(error.localizedDescription, privacy: .public)")
            consoleLog("Recording failed to start: \(error.localizedDescription)")
            await hideCapsuleAfterDelay()
        }
    }

    func pushToTalkKeyUp() async {
        logger.info("Push-to-talk key up")
        consoleLog("Push-to-talk key up")

        if isAwaitingCancelRecordingConfirmation {
            return
        }

        if ignoreNextShortcutKeyUp {
            ignoreNextShortcutKeyUp = false
            logger.debug("Ignoring key up after toggle stop")
            return
        }

        guard pushToTalkIsActive else {
            return
        }

        pushToTalkIsActive = false

        guard audioCaptureService.isRecording else {
            return
        }

        let holdDuration = Date().timeIntervalSince(currentShortcutPressStart ?? Date())
        currentShortcutPressStart = nil

        if holdDuration < toggleActivationThresholdSeconds {
            toggleRecordingIsActive = true
            transientMessage = "Listening... press shortcut again to stop."
            logger.info("Toggle recording engaged. holdDuration=\(holdDuration, privacy: .public)")
            let holdDurationText = holdDuration.formatted(.number.precision(.fractionLength(2)))
            consoleLog("Toggle recording engaged. holdDuration=\(holdDurationText)s")
            return
        }

        await stopRecordingAndTranscribe()
    }

    private func stopRecordingAndTranscribe() async {
        toggleRecordingIsActive = false
        isAwaitingCancelRecordingConfirmation = false
        sessionState = .transcribing
        floatingCapsuleController.showTranscribing()

        do {
            let audioURL = try audioCaptureService.stopRecording()
            defer { try? FileManager.default.removeItem(at: audioURL) }

            guard let selectedModelOption else {
                throw TranscriptionError.pipelineUnavailable
            }

            let audioDuration = transcriptionService.audioDurationSeconds(for: audioURL)
            startTranscriptionProgressTracking(audioDuration: audioDuration)
            let transcriptionStart = Date()

            let transcript = try await transcriptionService.transcribe(
                audioURL: audioURL,
                option: selectedModelOption,
                mode: transcriptionMode,
                prompt: transcriptionMode == .smart ? smartPrompt : nil
            )
            let transcriptionElapsed = Date().timeIntervalSince(transcriptionStart)
            updateTranscriptionSpeedEstimate(audioDuration: audioDuration, elapsed: transcriptionElapsed)
            stopTranscriptionProgressTracking(finalProgress: 1)

            let pasteResult = await pasteService.paste(text: transcript)
            logger.info("Transcription completed. characters=\(transcript.count, privacy: .public), pasteResult=\(String(describing: pasteResult), privacy: .public)")
            consoleLog("Transcription completed. characters=\(transcript.count), pasteResult=\(String(describing: pasteResult))")

            switch pasteResult {
            case .pasted:
                transientMessage = nil
            case .copiedOnly:
                transientMessage = "Copied transcript to clipboard. Enable Accessibility for auto-paste."
                await postPasteFallbackNotification()
            }

            lastError = nil
            sessionState = .idle
        } catch {
            reportIssue(error)
            lastError = error.localizedDescription
            transientMessage = "Transcription failed."
            sessionState = .error(error.localizedDescription)
            stopTranscriptionProgressTracking()
            floatingCapsuleController.showError("Transcription failed")
            logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            consoleLog("Transcription failed: \(error.localizedDescription)")
        }

        await hideCapsuleAfterDelay()
    }

    private var hasConfiguredShortcut: Bool {
        KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil
    }

    private func beginSetupFlow() {
        setupStep = .model
        didAutoPromptAccessibilityInSetup = false
        downloadSpeedText = nil
        downloadProgress = isSelectedModelDownloaded ? 1 : 0
        downloadStatus = isSelectedModelDownloaded ? "Model already downloaded." : ""
    }

    private func setupDownloadPrimaryButtonTapped() async {
        if !microphoneAuthorized {
            await microphonePermissionButtonTapped()
            refreshPermissionStatus()
            guard microphoneAuthorized else {
                return
            }
        }

        guard let option = selectedModelOption else {
            lastError = "Please select a valid model."
            return
        }

        if modelSetupService.isModelDownloaded(option) {
            completeSetup()
            return
        }

        await downloadModelButtonTapped()
    }

    private func completeSetup() {
        hasCompletedSetup = true
        transientMessage = "MacX is ready. Quick tap to toggle listening, or hold for push-to-talk."

        if isPreviewMode { return }

        closeSetupWindowButtonTapped()
        logger.info("Setup completed")
        consoleLog("Setup completed")
        Task { await warmModelTask() }
    }

    private func requestPermissionsForSetupIfNeeded() async {
        if isPreviewMode { return }
        refreshPermissionStatus()

        if permissionsService.microphonePermissionState() == .notDetermined {
            _ = await permissionsService.requestMicrophonePermission()
            refreshPermissionStatus()
        }

        guard !didAutoPromptAccessibilityInSetup else { return }
        didAutoPromptAccessibilityInSetup = true

        if !accessibilityAuthorized {
            permissionsService.promptForAccessibilityPermission()
            refreshPermissionStatus()
        }
    }

    private func registerShortcutHandlers() {
        if isPreviewMode { return }
        KeyboardShortcuts.removeHandler(for: .pushToTalk)

        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            Task {
                await self?.pushToTalkKeyDown()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            Task {
                await self?.pushToTalkKeyUp()
            }
        }
    }

    private func registerKeyboardMonitor() {
        if isPreviewMode { return }
        keyboardMonitorService.start { [weak self] keyPress in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.handleMonitoredKeyPress(keyPress)
            }
        }
    }

    private func handleMonitoredKeyPress(_ keyPress: KeyboardMonitorService.KeyPress) {
        guard case .recording = sessionState, audioCaptureService.isRecording else { return }

        if isAwaitingCancelRecordingConfirmation {
            resolveCancelRecordingConfirmation(with: keyPress)
            return
        }

        guard keyPress == .escape else { return }
        presentCancelRecordingConfirmation()
    }

    private func presentCancelRecordingConfirmation() {
        isAwaitingCancelRecordingConfirmation = true
        floatingCapsuleController.showCancelConfirmation()
        logger.info("Recording cancel confirmation shown")
        consoleLog("Recording cancel confirmation shown")
    }

    private func dismissCancelRecordingConfirmation() {
        guard isAwaitingCancelRecordingConfirmation else { return }

        isAwaitingCancelRecordingConfirmation = false
        guard case .recording = sessionState, audioCaptureService.isRecording else {
            floatingCapsuleController.hide()
            return
        }

        floatingCapsuleController.showRecording()
        logger.info("Recording cancel confirmation dismissed")
        consoleLog("Recording cancel confirmation dismissed")
    }

    private func resolveCancelRecordingConfirmation(with keyPress: KeyboardMonitorService.KeyPress) {
        switch keyPress {
        case .character("y"):
            cancelRecordingFromConfirmation()
        default:
            dismissCancelRecordingConfirmation()
        }
    }

    private func cancelRecordingFromConfirmation() {
        guard audioCaptureService.isRecording else {
            isAwaitingCancelRecordingConfirmation = false
            return
        }

        audioCaptureService.cancelRecording()

        isAwaitingCancelRecordingConfirmation = false
        pushToTalkIsActive = false
        toggleRecordingIsActive = false
        ignoreNextShortcutKeyUp = false
        currentShortcutPressStart = nil
        sessionState = .idle
        transientMessage = "Recording canceled."
        floatingCapsuleController.hide()
        logger.info("Recording canceled from keyboard confirmation")
        consoleLog("Recording canceled from keyboard confirmation")
    }

    private func refreshPermissionStatus() {
        if isPreviewMode { return }
        microphonePermissionState = permissionsService.microphonePermissionState()
        microphoneAuthorized = microphonePermissionState == .authorized
        accessibilityAuthorized = permissionsService.hasAccessibilityPermission()
    }

    private func showSetupWindow() {
        if isPreviewMode { return }
        refreshPermissionStatus()

        let controller = setupWindowController ?? SetupWindowController(model: self)
        setupWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func recordingLevelDidUpdate(_ level: Double) {
        guard case .recording = sessionState else { return }
        floatingCapsuleController.updateLevel(level)
    }

    private func warmModelTask() async {
        if isPreviewMode { return }
        guard let selectedModelOption else { return }
        logger.info("Warming model: \(selectedModelOption.rawValue, privacy: .public)")
        consoleLog("Warming model: \(selectedModelOption.rawValue)")

        do {
            try await transcriptionService.prepareModelIfNeeded(option: selectedModelOption)
            logger.info("Model warmup complete: \(selectedModelOption.rawValue, privacy: .public)")
            consoleLog("Model warmup complete: \(selectedModelOption.rawValue)")
        } catch {
            reportIssue(error)
            transientMessage = "Model will load on first transcription."
            logger.error("Model warmup failed: \(error.localizedDescription, privacy: .public)")
            consoleLog("Model warmup failed: \(error.localizedDescription)")
        }
    }

    private func hideCapsuleAfterDelay() async {
        try? await clock.sleep(for: .milliseconds(300))
        isAwaitingCancelRecordingConfirmation = false
        stopTranscriptionProgressTracking()
        floatingCapsuleController.hide()

        if case .error = sessionState {
            sessionState = .idle
        }
    }

    private func postPasteFallbackNotification() async {
        if isPreviewMode { return }
        let center = UNUserNotificationCenter.current()

        let settings = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }

        if settings.authorizationStatus == .notDetermined {
            _ = await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }

        let content = UNMutableNotificationContent()
        content.title = "MacX"
        content.body = "Transcript copied to clipboard. Paste manually with Command+V."

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume(returning: ())
            }
        }
    }

    private func consoleLog(_ message: String) {
        print("[macx] \(message)")
    }

    private func startTranscriptionProgressTracking(audioDuration: Double) {
        stopTranscriptionProgressTracking()
        let expectedDuration = estimatedTranscriptionDuration(for: audioDuration)
        let start = Date()

        transcriptionProgressTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let progress = min(max(elapsed / expectedDuration, 0), 0.97)
                self.floatingCapsuleController.updateTranscriptionProgress(progress)

                try? await self.clock.sleep(for: .milliseconds(120))
            }
        }
    }

    private func stopTranscriptionProgressTracking(finalProgress: Double? = nil) {
        transcriptionProgressTask?.cancel()
        transcriptionProgressTask = nil

        if let finalProgress {
            floatingCapsuleController.updateTranscriptionProgress(finalProgress)
        }
    }

    private func estimatedTranscriptionDuration(for audioDuration: Double) -> Double {
        guard audioDuration > 0 else { return 5 }
        let estimate = audioDuration / max(estimatedTranscriptionRTF, 0.2)
        return max(2, estimate)
    }

    private func updateTranscriptionSpeedEstimate(audioDuration: Double, elapsed: Double) {
        guard audioDuration > 0, elapsed > 0 else { return }
        let latestRTF = audioDuration / elapsed

        // Smooth updates so short clips do not swing the UI estimate heavily.
        let alpha = 0.25
        estimatedTranscriptionRTF = (1 - alpha) * estimatedTranscriptionRTF + alpha * latestRTF
    }
}

#if DEBUG
extension AppModel {
    static func makePreview(_ configure: (AppModel) -> Void = { _ in }) -> AppModel {
        let model = AppModel(isPreviewMode: true)
        model.hasCompletedSetup = true
        model.selectedModelID = ModelOption.defaultOption.rawValue
        model.setupStep = .model
        model.isDownloadingModel = false
        model.downloadProgress = 0
        model.downloadStatus = ""
        model.downloadSpeedText = nil
        model.sessionState = .idle
        model.lastError = nil
        model.transientMessage = nil
        model.microphonePermissionState = .authorized
        model.microphoneAuthorized = true
        model.accessibilityAuthorized = true
        configure(model)
        return model
    }
}
#endif
