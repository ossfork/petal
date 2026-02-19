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
    enum ProcessingStage: Equatable {
        case trimming
        case speeding
        case transcribing
    }

    enum SessionState: Equatable {
        case idle
        case recording
        case processing(ProcessingStage)
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
    @ObservationIgnored @Shared(.historyRetentionMode) private var historyRetentionModeStorage = HistoryRetentionMode.both.rawValue
    @ObservationIgnored @Shared(.transcriptHistoryDays) private var transcriptHistoryDaysStorage: [TranscriptHistoryDay] = []

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

    var historyRetentionMode: HistoryRetentionMode = .both {
        didSet {
            $historyRetentionModeStorage.withLock { $0 = historyRetentionMode.rawValue }
            transcriptHistoryDays = appHistoryClient.applyRetention(historyRetentionMode, transcriptHistoryDays)
        }
    }

    var transcriptHistoryDays: [TranscriptHistoryDay] = [] {
        didSet {
            $transcriptHistoryDaysStorage.withLock { $0 = transcriptHistoryDays }
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
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.appModelSetupClient) private var modelSetupClient
    @ObservationIgnored @Dependency(\.appTranscriptionClient) private var appTranscriptionClient
    @ObservationIgnored @Dependency(\.appPasteClient) private var appPasteClient
    @ObservationIgnored @Dependency(\.appPermissionsClient) private var appPermissionsClient
    @ObservationIgnored @Dependency(\.appAudioClient) private var appAudioClient
    @ObservationIgnored @Dependency(\.appKeyboardClient) private var appKeyboardClient
    @ObservationIgnored @Dependency(\.appFloatingCapsuleClient) private var appFloatingCapsuleClient
    @ObservationIgnored @Dependency(\.appSoundClient) private var appSoundClient
    @ObservationIgnored @Dependency(\.appHistoryClient) private var appHistoryClient
    @ObservationIgnored @Dependency(\.appLogClient) private var appLogClient
    @ObservationIgnored private let logger = Logger(subsystem: "com.optimalapps.gloam", category: "AppModel")

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
    @ObservationIgnored private var permissionMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var estimatedTranscriptionRTF = 2.2
    @ObservationIgnored private let toggleActivationThresholdSeconds = 2.0

    nonisolated private static var isRunningInSwiftUIPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    init(isPreviewMode: Bool = AppModel.isRunningInSwiftUIPreview) {
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
        historyRetentionMode = HistoryRetentionMode(rawValue: historyRetentionModeStorage) ?? .both
        transcriptHistoryDays = transcriptHistoryDaysStorage

        transcriptHistoryDays = appHistoryClient.bootstrap(historyRetentionMode, transcriptHistoryDays)

        registerShortcutHandlers()
        registerKeyboardMonitor()
        refreshPermissionStatus()
        startPermissionMonitoring()
        logger.info("AppModel initialized. setupCompleted=\(self.hasCompletedSetup, privacy: .public), model=\(self.selectedModelID, privacy: .public)")
        consoleLog("AppModel initialized. setupCompleted=\(self.hasCompletedSetup), model=\(self.selectedModelID)")

        Task { await appDidLaunch() }
    }

    var selectedModelOption: ModelOption? {
        ModelOption(rawValue: selectedModelID)
    }

    var isSelectedModelDownloaded: Bool {
        guard let selectedModelOption else { return false }
        return modelSetupClient.isModelDownloaded(selectedModelOption)
    }

    var statusTitle: String {
        switch sessionState {
        case .idle:
            return hasCompletedSetup ? "Ready" : "Setup Required"
        case .recording:
            return "REC"
        case let .processing(stage):
            switch stage {
            case .trimming:
                return "Trimming"
            case .speeding:
                return "Speeding"
            case .transcribing:
                return "Transcribing"
            }
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
        case let .processing(stage):
            switch stage {
            case .trimming:
                return "scissors"
            case .speeding:
                return "figure.run"
            case .transcribing:
                return "hourglass"
            }
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

    var recentTranscriptHistoryEntries: [TranscriptHistoryEntry] {
        transcriptHistoryDays
            .flatMap(\.entries)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(20)
            .map { $0 }
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

    var modelsDirectoryDisplayPath: String {
        appHistoryClient.modelsDirectoryPath()
    }

    var historyDirectoryDisplayPath: String {
        appHistoryClient.historyDirectoryPath()
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
            try await modelSetupClient.downloadModel(option) { update in
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

        let granted = await appPermissionsClient.requestMicrophonePermission()
        refreshPermissionStatus()
        logger.info("Microphone permission request resolved. granted=\(granted, privacy: .public), authorized=\(self.microphoneAuthorized, privacy: .public)")
        consoleLog("Microphone permission request resolved. granted=\(granted), authorized=\(self.microphoneAuthorized)")

        if granted || microphoneAuthorized {
            lastError = nil
            return
        }

        if microphonePermissionState == .denied {
            appPermissionsClient.openMicrophonePrivacySettings()
            lastError = "Enable microphone access in System Settings, then return to Gloam."
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

        appPermissionsClient.promptForAccessibilityPermission()
        refreshPermissionStatus()
        logger.info("Accessibility permission prompt shown. authorized=\(self.accessibilityAuthorized, privacy: .public)")
        consoleLog("Accessibility permission prompt shown. authorized=\(self.accessibilityAuthorized)")

        if !accessibilityAuthorized {
            appPermissionsClient.openAccessibilityPrivacySettings()
            transientMessage = "Enable Accessibility to allow automatic paste."
        }
    }

    func copyTranscriptHistoryButtonTapped(_ entryID: UUID) {
        guard
            let entry = transcriptHistoryDays
                .flatMap(\.entries)
                .first(where: { $0.id == entryID })
        else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formattedHistoryEntry(entry), forType: .string)
        transientMessage = "Copied transcript history entry."
    }

    func historyTimestampText(for entry: TranscriptHistoryEntry) -> String {
        entry.timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    func historyMetadataText(for entry: TranscriptHistoryEntry) -> String {
        let elapsed = entry.transcriptionElapsedSeconds.formatted(.number.precision(.fractionLength(2)))
        let audio = entry.audioDurationSeconds.formatted(.number.precision(.fractionLength(2)))
        let persisted = entry.transcriptRelativePath != nil || entry.audioRelativePath != nil ? "saved" : "not saved"
        return "\(entry.transcriptionMode.capitalized) • \(entry.modelID) • \(entry.characterCount) chars • \(elapsed)s elapsed • \(audio)s audio • \(persisted)"
    }

    func openHistoryFolderButtonTapped() {
        let opened = appHistoryClient.openHistoryFolder(historyRetentionMode)
        if !opened {
            transientMessage = "History retention is off."
        }
    }

    func playHistoryAudioButtonTapped(_ entryID: UUID) {
        guard
            let entry = transcriptHistoryDays.flatMap(\.entries).first(where: { $0.id == entryID }),
            let audioRelativePath = entry.audioRelativePath
        else {
            transientMessage = "No saved audio for this entry."
            return
        }

        guard let audioURL = appHistoryClient.historyAudioURL(audioRelativePath) else {
            transientMessage = "Saved audio file not found."
            return
        }

        NSWorkspace.shared.open(audioURL)
    }

    func handleDeepLink(_ command: GloamDeepLinkCommand) async {
        switch command {
        case .start:
            await startRecordingFromDeepLink()
        case .stop:
            await stopRecordingFromDeepLink()
        case .toggle:
            await toggleRecordingFromDeepLink()
        case .setup:
            changeModelButtonTapped()
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

        if toggleRecordingIsActive, !appAudioClient.isRecording() {
            toggleRecordingIsActive = false
        }

        if toggleRecordingIsActive, appAudioClient.isRecording() {
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
        currentShortcutPressStart = now

        if !microphoneAuthorized {
            await microphonePermissionButtonTapped()
            refreshPermissionStatus()

            guard microphoneAuthorized else {
                sessionState = .error("Microphone permission denied")
                transientMessage = "Enable microphone access to record."
                pushToTalkIsActive = false
                currentShortcutPressStart = nil
                appFloatingCapsuleClient.showError("Microphone denied")
                await hideCapsuleAfterDelay()
                return
            }
        }

        do {
            try appAudioClient.startRecording { [weak self] level in
                guard let self else { return }
                Task { @MainActor [self, level] in
                    self.recordingLevelDidUpdate(level)
                }
            }

            isAwaitingCancelRecordingConfirmation = false
            sessionState = .recording
            appSoundClient.playRecordingStarted()
            appFloatingCapsuleClient.showRecording()
            logger.info("Recording started")
            consoleLog("Recording started")
        } catch {
            reportIssue(error)
            sessionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
            pushToTalkIsActive = false
            currentShortcutPressStart = nil
            appFloatingCapsuleClient.showError("Recording failed")
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

        guard appAudioClient.isRecording() else {
            return
        }

        let holdDuration = now.timeIntervalSince(currentShortcutPressStart ?? now)
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
        sessionState = .processing(.trimming)
        appFloatingCapsuleClient.showTrimming()

        do {
            let audioURL = try appAudioClient.stopRecording()
            defer { try? FileManager.default.removeItem(at: audioURL) }

            guard let selectedModelOption else {
                throw TranscriptionError.pipelineUnavailable
            }

            let audioDuration = appTranscriptionClient.audioDurationSeconds(audioURL)
            if autoSpeedRate(for: audioDuration) != nil {
                sessionState = .processing(.speeding)
                appFloatingCapsuleClient.showSpeeding()
            }

            sessionState = .processing(.transcribing)
            appFloatingCapsuleClient.showTranscribing()
            appSoundClient.playTranscriptionStarted()
            startTranscriptionProgressTracking(audioDuration: audioDuration)
            let transcriptionStart = now

            let transcript = try await appTranscriptionClient.transcribe(
                audioURL,
                selectedModelOption,
                transcriptionMode,
                transcriptionMode == .smart ? smartPrompt : nil
            )
            let transcriptionElapsed = now.timeIntervalSince(transcriptionStart)
            updateTranscriptionSpeedEstimate(audioDuration: audioDuration, elapsed: transcriptionElapsed)
            stopTranscriptionProgressTracking(finalProgress: 1)
            appSoundClient.playTranscriptionCompleted()

            let pasteResult = await appPasteClient.paste(transcript)
            logger.info("Transcription completed. characters=\(transcript.count, privacy: .public), pasteResult=\(String(describing: pasteResult), privacy: .public)")
            consoleLog("Transcription completed. characters=\(transcript.count), pasteResult=\(String(describing: pasteResult))")
            appLogClient.dumpDebug(
                "AppModel",
                "Transcription metrics",
                appDumpString(
                    [
                        "characters": "\(transcript.count)",
                        "audioDuration": audioDuration.formatted(.number.precision(.fractionLength(2))),
                        "transcriptionElapsed": transcriptionElapsed.formatted(.number.precision(.fractionLength(2))),
                        "pasteResult": pasteResult.rawValue
                    ]
                )
            )

            let persistedPaths = persistHistoryArtifacts(
                audioURL: audioURL,
                transcript: transcript,
                timestamp: transcriptionStart,
                mode: transcriptionMode.rawValue,
                modelID: selectedModelOption.rawValue
            )

            appendTranscriptHistory(
                transcript: transcript,
                modelID: selectedModelOption.rawValue,
                mode: transcriptionMode.rawValue,
                audioDuration: audioDuration,
                transcriptionElapsed: transcriptionElapsed,
                pasteResult: pasteResult,
                audioRelativePath: persistedPaths?.audioRelativePath,
                transcriptRelativePath: persistedPaths?.transcriptRelativePath
            )

            switch pasteResult {
            case .pasted:
                transientMessage = nil
            case .copiedOnly:
                transientMessage = "Auto-paste unavailable. Enable Accessibility to paste into the focused app automatically."
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
            appFloatingCapsuleClient.showError("Transcription failed")
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

        if modelSetupClient.isModelDownloaded(option) {
            completeSetup()
            return
        }

        await downloadModelButtonTapped()
    }

    private func completeSetup() {
        hasCompletedSetup = true
        transientMessage = "Gloam is ready. Quick tap to toggle listening, or hold for push-to-talk."

        if isPreviewMode { return }

        closeSetupWindowButtonTapped()
        logger.info("Setup completed")
        consoleLog("Setup completed")
        Task { await warmModelTask() }
    }

    private func requestPermissionsForSetupIfNeeded() async {
        if isPreviewMode { return }
        refreshPermissionStatus()

        if appPermissionsClient.microphonePermissionState() == .notDetermined {
            _ = await appPermissionsClient.requestMicrophonePermission()
            refreshPermissionStatus()
        }

        guard !didAutoPromptAccessibilityInSetup else { return }
        didAutoPromptAccessibilityInSetup = true

        if !accessibilityAuthorized {
            appPermissionsClient.promptForAccessibilityPermission()
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
        appKeyboardClient.start { [weak self] keyPress in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.handleMonitoredKeyPress(keyPress)
            }
        }
    }

    private func handleMonitoredKeyPress(_ keyPress: AppKeyPress) {
        guard case .recording = sessionState, appAudioClient.isRecording() else { return }

        if isAwaitingCancelRecordingConfirmation {
            resolveCancelRecordingConfirmation(with: keyPress)
            return
        }

        guard keyPress == .escape else { return }
        presentCancelRecordingConfirmation()
    }

    private func presentCancelRecordingConfirmation() {
        isAwaitingCancelRecordingConfirmation = true
        appFloatingCapsuleClient.showCancelConfirmation()
        logger.info("Recording cancel confirmation shown")
        consoleLog("Recording cancel confirmation shown")
    }

    private func dismissCancelRecordingConfirmation() {
        guard isAwaitingCancelRecordingConfirmation else { return }

        isAwaitingCancelRecordingConfirmation = false
        guard case .recording = sessionState, appAudioClient.isRecording() else {
            appFloatingCapsuleClient.hide()
            return
        }

        appFloatingCapsuleClient.showRecording()
        logger.info("Recording cancel confirmation dismissed")
        consoleLog("Recording cancel confirmation dismissed")
    }

    private func resolveCancelRecordingConfirmation(with keyPress: AppKeyPress) {
        switch keyPress {
        case .character("y"):
            cancelRecordingFromConfirmation()
        default:
            dismissCancelRecordingConfirmation()
        }
    }

    private func cancelRecordingFromConfirmation() {
        guard appAudioClient.isRecording() else {
            isAwaitingCancelRecordingConfirmation = false
            return
        }

        appAudioClient.cancelRecording()

        isAwaitingCancelRecordingConfirmation = false
        pushToTalkIsActive = false
        toggleRecordingIsActive = false
        ignoreNextShortcutKeyUp = false
        currentShortcutPressStart = nil
        sessionState = .idle
        transientMessage = "Recording canceled."
        appFloatingCapsuleClient.hide()
        logger.info("Recording canceled from keyboard confirmation")
        consoleLog("Recording canceled from keyboard confirmation")
    }

    private func refreshPermissionStatus() {
        if isPreviewMode { return }
        microphonePermissionState = appPermissionsClient.microphonePermissionState()
        microphoneAuthorized = microphonePermissionState == .authorized
        accessibilityAuthorized = appPermissionsClient.hasAccessibilityPermission()
    }

    private func showSetupWindow() {
        if isPreviewMode { return }
        refreshPermissionStatus()

        let controller = setupWindowController ?? SetupWindowController(model: self)
        setupWindowController = controller

        if let setupWindow = controller.window {
            for window in NSApp.windows {
                guard
                    window !== setupWindow,
                    window.identifier?.rawValue == "GloamSetupWindow"
                else { continue }
                window.close()
            }
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.collectionBehavior.insert(.moveToActiveSpace)
        controller.window?.collectionBehavior.insert(.fullScreenAuxiliary)
        controller.window?.orderFrontRegardless()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startPermissionMonitoring() {
        permissionMonitorTask?.cancel()
        permissionMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshPermissionStatus()
                try? await self.clock.sleep(for: .seconds(1))
            }
        }
    }

    private func startRecordingFromDeepLink() async {
        guard hasCompletedSetup else {
            transientMessage = "Complete setup before recording."
            beginSetupFlow()
            showSetupWindow()
            return
        }

        if appAudioClient.isRecording() || isProcessing {
            return
        }

        if !microphoneAuthorized {
            await microphonePermissionButtonTapped()
            refreshPermissionStatus()
            guard microphoneAuthorized else { return }
        }

        do {
            try appAudioClient.startRecording { [weak self] level in
                guard let self else { return }
                Task { @MainActor [self, level] in
                    self.recordingLevelDidUpdate(level)
                }
            }

            isAwaitingCancelRecordingConfirmation = false
            pushToTalkIsActive = false
            toggleRecordingIsActive = true
            ignoreNextShortcutKeyUp = false
            currentShortcutPressStart = nil
            sessionState = .recording
            transientMessage = "Listening... use gloam://stop to transcribe."
            appSoundClient.playRecordingStarted()
            appFloatingCapsuleClient.showRecording()
            logger.info("Recording started from deep link")
            consoleLog("Recording started from deep link")
        } catch {
            reportIssue(error)
            sessionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
            appFloatingCapsuleClient.showError("Recording failed")
            logger.error("Deep link start failed: \(error.localizedDescription, privacy: .public)")
            consoleLog("Deep link start failed: \(error.localizedDescription)")
            await hideCapsuleAfterDelay()
        }
    }

    private func stopRecordingFromDeepLink() async {
        guard appAudioClient.isRecording() else { return }
        logger.info("Stopping recording from deep link")
        consoleLog("Stopping recording from deep link")
        await stopRecordingAndTranscribe()
    }

    private func toggleRecordingFromDeepLink() async {
        if appAudioClient.isRecording() {
            await stopRecordingFromDeepLink()
        } else {
            await startRecordingFromDeepLink()
        }
    }

    private func recordingLevelDidUpdate(_ level: Double) {
        guard case .recording = sessionState else { return }
        appFloatingCapsuleClient.updateLevel(level)
    }

    private func warmModelTask() async {
        if isPreviewMode { return }
        guard let selectedModelOption else { return }
        logger.info("Warming model: \(selectedModelOption.rawValue, privacy: .public)")
        consoleLog("Warming model: \(selectedModelOption.rawValue)")

        do {
            try await appTranscriptionClient.prepareModelIfNeeded(selectedModelOption)
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
        appFloatingCapsuleClient.hide()

        if case .error = sessionState {
            sessionState = .idle
        }
    }

    private var isProcessing: Bool {
        if case .processing = sessionState {
            return true
        }
        return false
    }

    private func autoSpeedRate(for audioDuration: Double) -> Double? {
        switch audioDuration {
        case ..<45:
            return nil
        case 45..<90:
            return 1.1
        case 90..<180:
            return 1.2
        default:
            return 1.25
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
        content.title = "Gloam"
        content.body = "Transcript copied to clipboard. Paste manually with Command+V."

        let request = UNNotificationRequest(
            identifier: uuid().uuidString,
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
        appLogClient.debug("AppModel", message)
    }

    private func startTranscriptionProgressTracking(audioDuration: Double) {
        stopTranscriptionProgressTracking()
        let expectedDuration = estimatedTranscriptionDuration(for: audioDuration)
        let start = now

        transcriptionProgressTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let elapsed = now.timeIntervalSince(start)
                let progress = min(max(elapsed / expectedDuration, 0), 0.97)
                self.appFloatingCapsuleClient.updateTranscriptionProgress(progress)

                try? await self.clock.sleep(for: .milliseconds(120))
            }
        }
    }

    private func stopTranscriptionProgressTracking(finalProgress: Double? = nil) {
        transcriptionProgressTask?.cancel()
        transcriptionProgressTask = nil

        if let finalProgress {
            appFloatingCapsuleClient.updateTranscriptionProgress(finalProgress)
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

    private func appendTranscriptHistory(
        transcript: String,
        modelID: String,
        mode: String,
        audioDuration: Double,
        transcriptionElapsed: Double,
        pasteResult: PasteResult,
        audioRelativePath: String?,
        transcriptRelativePath: String?
    ) {
        transcriptHistoryDays = appHistoryClient.appendEntry(
            transcriptHistoryDays,
            transcript,
            modelID,
            mode,
            audioDuration,
            transcriptionElapsed,
            pasteResult,
            audioRelativePath,
            transcriptRelativePath,
            historyRetentionMode,
            now,
            uuid()
        )
    }

    private func persistHistoryArtifacts(
        audioURL: URL,
        transcript: String,
        timestamp: Date,
        mode: String,
        modelID: String
    ) -> (audioRelativePath: String?, transcriptRelativePath: String?)? {
        let artifacts = appHistoryClient.persistArtifacts(
            audioURL,
            transcript,
            timestamp,
            mode,
            modelID,
            historyRetentionMode
        )
        return (
            audioRelativePath: artifacts?.audioRelativePath,
            transcriptRelativePath: artifacts?.transcriptRelativePath
        )
    }

    private func formattedHistoryEntry(_ entry: TranscriptHistoryEntry) -> String {
        let timestamp = entry.timestamp.formatted(date: .abbreviated, time: .standard)
        let elapsed = entry.transcriptionElapsedSeconds.formatted(.number.precision(.fractionLength(2)))
        let audio = entry.audioDurationSeconds.formatted(.number.precision(.fractionLength(2)))
        let audioPath = entry.audioRelativePath ?? "not saved"
        let transcriptPath = entry.transcriptRelativePath ?? "not saved"

        return """
        Timestamp: \(timestamp)
        Model: \(entry.modelID)
        Mode: \(entry.transcriptionMode)
        Paste: \(entry.pasteResult)
        Duration: \(audio)s audio, \(elapsed)s transcription
        Characters: \(entry.characterCount)
        Audio file: \(audioPath)
        Transcript file: \(transcriptPath)

        \(entry.transcript.isEmpty ? "Transcript not retained." : entry.transcript)
        """
    }

    deinit {
        transcriptionProgressTask?.cancel()
        permissionMonitorTask?.cancel()
    }
}

private struct AppModelDownloadUpdate: Sendable {
    var fractionCompleted: Double
    var status: String
    var speedText: String?
}

private struct AppModelSetupClient {
    var isModelDownloaded: @MainActor (ModelOption) -> Bool = { _ in false }
    var downloadModel: @MainActor (ModelOption, @escaping @Sendable (AppModelDownloadUpdate) -> Void) async throws -> Void
}

private struct AppTranscriptionClient {
    var prepareModelIfNeeded: @MainActor (ModelOption) async throws -> Void
    var transcribe: @MainActor (URL, ModelOption, TranscriptionMode, String?) async throws -> String
    var audioDurationSeconds: @MainActor (URL) -> Double = { _ in 0 }
}

private struct AppPasteClient {
    var paste: @MainActor (String) async -> PasteResult = { _ in .copiedOnly }
}

private struct AppPermissionsClient {
    var microphonePermissionState: @MainActor () -> MicrophonePermissionState = { .notDetermined }
    var requestMicrophonePermission: @MainActor () async -> Bool = { false }
    var hasAccessibilityPermission: @MainActor () -> Bool = { false }
    var promptForAccessibilityPermission: @MainActor () -> Void = {}
    var openMicrophonePrivacySettings: @MainActor () -> Void = {}
    var openAccessibilityPrivacySettings: @MainActor () -> Void = {}
}

private struct AppAudioClient {
    var isRecording: @MainActor () -> Bool = { false }
    var startRecording: @MainActor (@escaping @Sendable (Double) -> Void) throws -> Void
    var stopRecording: @MainActor () throws -> URL
    var cancelRecording: @MainActor () -> Void = {}
}

private enum AppKeyPress: Equatable, Sendable {
    case escape
    case character(Character)
    case other
}

private struct AppKeyboardClient {
    var start: @MainActor (@escaping @Sendable (AppKeyPress) -> Void) -> Void = { _ in }
    var stop: @MainActor () -> Void = {}
}

private struct AppFloatingCapsuleClient {
    var showRecording: @MainActor () -> Void = {}
    var showTrimming: @MainActor () -> Void = {}
    var showSpeeding: @MainActor () -> Void = {}
    var updateLevel: @MainActor (Double) -> Void = { _ in }
    var showTranscribing: @MainActor () -> Void = {}
    var updateTranscriptionProgress: @MainActor (Double) -> Void = { _ in }
    var showCancelConfirmation: @MainActor () -> Void = {}
    var showError: @MainActor (String) -> Void = { _ in }
    var hide: @MainActor () -> Void = {}
}

private struct AppSoundClient {
    var playRecordingStarted: @MainActor () -> Void = {}
    var playTranscriptionStarted: @MainActor () -> Void = {}
    var playTranscriptionCompleted: @MainActor () -> Void = {}
}

private struct AppHistoryArtifacts: Sendable {
    var audioRelativePath: String?
    var transcriptRelativePath: String?
}

private struct AppHistoryClient {
    var modelsDirectoryPath: @MainActor () -> String
    var historyDirectoryPath: @MainActor () -> String
    var bootstrap: @MainActor (HistoryRetentionMode, [TranscriptHistoryDay]) -> [TranscriptHistoryDay]
    var applyRetention: @MainActor (HistoryRetentionMode, [TranscriptHistoryDay]) -> [TranscriptHistoryDay]
    var appendEntry: @MainActor (
        [TranscriptHistoryDay],
        String,
        String,
        String,
        Double,
        Double,
        PasteResult,
        String?,
        String?,
        HistoryRetentionMode,
        Date,
        UUID
    ) -> [TranscriptHistoryDay]
    var persistArtifacts: @MainActor (URL, String, Date, String, String, HistoryRetentionMode) -> AppHistoryArtifacts?
    var openHistoryFolder: @MainActor (HistoryRetentionMode) -> Bool
    var historyAudioURL: @MainActor (String?) -> URL?
}

private enum AppModelSetupClientKey: DependencyKey {
    static var liveValue: AppModelSetupClient {
        AppModelSetupClient(
            isModelDownloaded: { option in
                LiveAppServiceContainer.modelSetupService.isModelDownloaded(option)
            },
            downloadModel: { option, progress in
                try await LiveAppServiceContainer.modelSetupService.downloadModel(option) { update in
                    progress(
                        AppModelDownloadUpdate(
                            fractionCompleted: update.fractionCompleted,
                            status: update.status,
                            speedText: update.speedText
                        )
                    )
                }
            }
        )
    }

    static var testValue: AppModelSetupClient {
        AppModelSetupClient(
            isModelDownloaded: { _ in false },
            downloadModel: { _, _ in }
        )
    }
}

private enum AppTranscriptionClientKey: DependencyKey {
    static var liveValue: AppTranscriptionClient {
        AppTranscriptionClient(
            prepareModelIfNeeded: { option in
                try await LiveAppServiceContainer.transcriptionService.prepareModelIfNeeded(option: option, pipelineModel: option.pipelineModel)
            },
            transcribe: { audioURL, option, mode, prompt in
                try await LiveAppServiceContainer.transcriptionService.transcribe(
                    audioURL: audioURL,
                    option: option,
                    pipelineModel: option.pipelineModel,
                    mode: mode,
                    prompt: prompt
                )
            },
            audioDurationSeconds: { url in
                LiveAppServiceContainer.transcriptionService.audioDurationSeconds(for: url)
            }
        )
    }

    static var testValue: AppTranscriptionClient {
        AppTranscriptionClient(
            prepareModelIfNeeded: { _ in },
            transcribe: { _, _, _, _ in "Test transcription" },
            audioDurationSeconds: { _ in 1 }
        )
    }
}

private enum AppPasteClientKey: DependencyKey {
    static var liveValue: AppPasteClient {
        AppPasteClient(
            paste: { text in
                await LiveAppServiceContainer.pasteService.paste(text: text)
            }
        )
    }

    static var testValue: AppPasteClient {
        AppPasteClient(
            paste: { _ in .pasted }
        )
    }
}

private enum AppPermissionsClientKey: DependencyKey {
    static var liveValue: AppPermissionsClient {
        AppPermissionsClient(
            microphonePermissionState: {
                LiveAppServiceContainer.permissionsService.microphonePermissionState()
            },
            requestMicrophonePermission: {
                await LiveAppServiceContainer.permissionsService.requestMicrophonePermission()
            },
            hasAccessibilityPermission: {
                LiveAppServiceContainer.permissionsService.hasAccessibilityPermission()
            },
            promptForAccessibilityPermission: {
                LiveAppServiceContainer.permissionsService.promptForAccessibilityPermission()
            },
            openMicrophonePrivacySettings: {
                LiveAppServiceContainer.permissionsService.openMicrophonePrivacySettings()
            },
            openAccessibilityPrivacySettings: {
                LiveAppServiceContainer.permissionsService.openAccessibilityPrivacySettings()
            }
        )
    }

    static var testValue: AppPermissionsClient {
        AppPermissionsClient(
            microphonePermissionState: { .authorized },
            requestMicrophonePermission: { true },
            hasAccessibilityPermission: { true },
            promptForAccessibilityPermission: {},
            openMicrophonePrivacySettings: {},
            openAccessibilityPrivacySettings: {}
        )
    }
}

private enum AppAudioClientKey: DependencyKey {
    static var liveValue: AppAudioClient {
        AppAudioClient(
            isRecording: {
                LiveAppServiceContainer.audioCaptureService.isRecording
            },
            startRecording: { levelHandler in
                try LiveAppServiceContainer.audioCaptureService.startRecording(levelHandler: levelHandler)
            },
            stopRecording: {
                try LiveAppServiceContainer.audioCaptureService.stopRecording()
            },
            cancelRecording: {
                LiveAppServiceContainer.audioCaptureService.cancelRecording()
            }
        )
    }

    static var testValue: AppAudioClient {
        AppAudioClient(
            isRecording: { false },
            startRecording: { _ in },
            stopRecording: { URL(fileURLWithPath: "/dev/null") },
            cancelRecording: {}
        )
    }
}

private enum AppKeyboardClientKey: DependencyKey {
    static var liveValue: AppKeyboardClient {
        AppKeyboardClient(
            start: { handler in
                LiveAppServiceContainer.keyboardMonitorService.start { keyPress in
                    switch keyPress {
                    case .escape:
                        handler(.escape)
                    case let .character(character):
                        handler(.character(character))
                    case .other:
                        handler(.other)
                    }
                }
            },
            stop: {
                LiveAppServiceContainer.keyboardMonitorService.stop()
            }
        )
    }

    static var testValue: AppKeyboardClient {
        AppKeyboardClient(
            start: { _ in },
            stop: {}
        )
    }
}

private enum AppFloatingCapsuleClientKey: DependencyKey {
    static var liveValue: AppFloatingCapsuleClient {
        AppFloatingCapsuleClient(
            showRecording: {
                LiveAppServiceContainer.floatingCapsuleController.showRecording()
            },
            showTrimming: {
                LiveAppServiceContainer.floatingCapsuleController.showTrimming()
            },
            showSpeeding: {
                LiveAppServiceContainer.floatingCapsuleController.showSpeeding()
            },
            updateLevel: { level in
                LiveAppServiceContainer.floatingCapsuleController.updateLevel(level)
            },
            showTranscribing: {
                LiveAppServiceContainer.floatingCapsuleController.showTranscribing()
            },
            updateTranscriptionProgress: { progress in
                LiveAppServiceContainer.floatingCapsuleController.updateTranscriptionProgress(progress)
            },
            showCancelConfirmation: {
                LiveAppServiceContainer.floatingCapsuleController.showCancelConfirmation()
            },
            showError: { message in
                LiveAppServiceContainer.floatingCapsuleController.showError(message)
            },
            hide: {
                LiveAppServiceContainer.floatingCapsuleController.hide()
            }
        )
    }

    static var testValue: AppFloatingCapsuleClient {
        AppFloatingCapsuleClient(
            showRecording: {},
            showTrimming: {},
            showSpeeding: {},
            updateLevel: { _ in },
            showTranscribing: {},
            updateTranscriptionProgress: { _ in },
            showCancelConfirmation: {},
            showError: { _ in },
            hide: {}
        )
    }
}

private enum AppSoundClientKey: DependencyKey {
    static var liveValue: AppSoundClient {
        AppSoundClient(
            playRecordingStarted: {
                LiveAppServiceContainer.soundEffectService.play(.recordingStarted)
            },
            playTranscriptionStarted: {
                LiveAppServiceContainer.soundEffectService.play(.transcriptionStarted)
            },
            playTranscriptionCompleted: {
                LiveAppServiceContainer.soundEffectService.play(.transcriptionCompleted)
            }
        )
    }

    static var testValue: AppSoundClient {
        AppSoundClient(
            playRecordingStarted: {},
            playTranscriptionStarted: {},
            playTranscriptionCompleted: {}
        )
    }
}

private enum AppHistoryClientKey: DependencyKey {
    static var liveValue: AppHistoryClient {
        AppHistoryClient(
            modelsDirectoryPath: {
                LiveAppServiceContainer.historyStoreService.modelsDirectoryPath
            },
            historyDirectoryPath: {
                LiveAppServiceContainer.historyStoreService.historyDirectoryPath
            },
            bootstrap: { retentionMode, storedDays in
                LiveAppServiceContainer.historyStoreService.bootstrap(
                    retentionMode: retentionMode,
                    storedDays: storedDays
                )
            },
            applyRetention: { retentionMode, currentDays in
                LiveAppServiceContainer.historyStoreService.applyRetention(
                    retentionMode,
                    to: currentDays
                )
            },
            appendEntry: { days, transcript, modelID, mode, audioDuration, transcriptionElapsed, pasteResult, audioRelativePath, transcriptRelativePath, retentionMode, timestamp, id in
                LiveAppServiceContainer.historyStoreService.appendEntry(
                    currentDays: days,
                    transcript: transcript,
                    modelID: modelID,
                    mode: mode,
                    audioDuration: audioDuration,
                    transcriptionElapsed: transcriptionElapsed,
                    pasteResult: pasteResult,
                    audioRelativePath: audioRelativePath,
                    transcriptRelativePath: transcriptRelativePath,
                    retentionMode: retentionMode,
                    timestamp: timestamp,
                    id: id
                )
            },
            persistArtifacts: { audioURL, transcript, timestamp, mode, modelID, retentionMode in
                let artifacts = LiveAppServiceContainer.historyStoreService.persistArtifacts(
                    audioURL: audioURL,
                    transcript: transcript,
                    timestamp: timestamp,
                    mode: mode,
                    modelID: modelID,
                    retentionMode: retentionMode
                )
                return AppHistoryArtifacts(
                    audioRelativePath: artifacts?.audioRelativePath,
                    transcriptRelativePath: artifacts?.transcriptRelativePath
                )
            },
            openHistoryFolder: { retentionMode in
                LiveAppServiceContainer.historyStoreService.openHistoryFolder(retentionMode: retentionMode)
            },
            historyAudioURL: { relativePath in
                LiveAppServiceContainer.historyStoreService.historyAudioURL(relativePath: relativePath)
            }
        )
    }

    static var testValue: AppHistoryClient {
        AppHistoryClient(
            modelsDirectoryPath: { "/tmp/Gloam/models" },
            historyDirectoryPath: { "/tmp/Gloam/history" },
            bootstrap: { _, days in days },
            applyRetention: { _, days in days },
            appendEntry: { days, _, _, _, _, _, _, _, _, _, _, _ in days },
            persistArtifacts: { _, _, _, _, _, _ in nil },
            openHistoryFolder: { _ in true },
            historyAudioURL: { _ in nil }
        )
    }
}

private extension DependencyValues {
    var appModelSetupClient: AppModelSetupClient {
        get { self[AppModelSetupClientKey.self] }
        set { self[AppModelSetupClientKey.self] = newValue }
    }

    var appTranscriptionClient: AppTranscriptionClient {
        get { self[AppTranscriptionClientKey.self] }
        set { self[AppTranscriptionClientKey.self] = newValue }
    }

    var appPasteClient: AppPasteClient {
        get { self[AppPasteClientKey.self] }
        set { self[AppPasteClientKey.self] = newValue }
    }

    var appPermissionsClient: AppPermissionsClient {
        get { self[AppPermissionsClientKey.self] }
        set { self[AppPermissionsClientKey.self] = newValue }
    }

    var appAudioClient: AppAudioClient {
        get { self[AppAudioClientKey.self] }
        set { self[AppAudioClientKey.self] = newValue }
    }

    var appKeyboardClient: AppKeyboardClient {
        get { self[AppKeyboardClientKey.self] }
        set { self[AppKeyboardClientKey.self] = newValue }
    }

    var appFloatingCapsuleClient: AppFloatingCapsuleClient {
        get { self[AppFloatingCapsuleClientKey.self] }
        set { self[AppFloatingCapsuleClientKey.self] = newValue }
    }

    var appSoundClient: AppSoundClient {
        get { self[AppSoundClientKey.self] }
        set { self[AppSoundClientKey.self] = newValue }
    }

    var appHistoryClient: AppHistoryClient {
        get { self[AppHistoryClientKey.self] }
        set { self[AppHistoryClientKey.self] = newValue }
    }
}

@MainActor
private enum LiveAppServiceContainer {
    static let modelSetupService = ModelSetupService()
    static let transcriptionService: TranscriptionService = {
        @Dependency(\.appLogClient) var appLogClient
        return TranscriptionService(appLogClient: appLogClient)
    }()
    static let pasteService = PasteService()
    static let permissionsService = PermissionsService()
    static let audioCaptureService = AudioCaptureService()
    static let keyboardMonitorService = KeyboardMonitorService()
    static let floatingCapsuleController = FloatingCapsuleController()
    static let soundEffectService = SoundEffectService()
    static let historyStoreService = HistoryStoreService()
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
        model.transcriptHistoryDays = []
        model.microphonePermissionState = .authorized
        model.microphoneAuthorized = true
        model.accessibilityAuthorized = true
        configure(model)
        return model
    }
}
#endif
