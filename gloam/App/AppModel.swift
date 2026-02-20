import AppKit
import AudioClient
import DownloadClient
import FloatingCapsuleClient
import Foundation
import HistoryClient
import IssueReporting
import KeyboardClient
import KeyboardShortcuts
import LogClient
import Observation
import Onboarding
import os
import PasteClient
import PermissionsClient
import Sauce
import Shared
import SoundClient
import TranscriptionClient
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
            transcriptHistoryDays = historyClient.applyRetention(historyRetentionMode, transcriptHistoryDays)
        }
    }

    var transcriptHistoryDays: [TranscriptHistoryDay] = [] {
        didSet {
            $transcriptHistoryDaysStorage.withLock { $0 = transcriptHistoryDays }
        }
    }

    var sessionState: SessionState = .idle
    var lastError: String?
    var transientMessage: String?
    var microphonePermissionState: MicrophonePermissionState = .notDetermined
    var microphoneAuthorized = false
    var accessibilityAuthorized = false

    var setupModel: SetupModel?

    @ObservationIgnored @Dependency(\.continuousClock) private var clock
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.downloadClient) private var downloadClient
    @ObservationIgnored @Dependency(\.transcriptionClient) private var transcriptionClient
    @ObservationIgnored @Dependency(\.pasteClient) private var pasteClient
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.audioClient) private var audioClient
    @ObservationIgnored @Dependency(\.keyboardClient) private var keyboardClient
    @ObservationIgnored @Dependency(\.floatingCapsuleClient) private var floatingCapsuleClient
    @ObservationIgnored @Dependency(\.soundClient) private var soundClient
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    @ObservationIgnored @Dependency(\.logClient) private var logClient
    @ObservationIgnored private let logger = Logger(subsystem: "com.optimalapps.gloam", category: "AppModel")

    @ObservationIgnored private let isPreviewMode: Bool

    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var pushToTalkIsActive = false
    @ObservationIgnored private var toggleRecordingIsActive = false
    @ObservationIgnored private var isAwaitingCancelRecordingConfirmation = false
    @ObservationIgnored private var ignoreNextShortcutKeyUp = false
    @ObservationIgnored private var currentShortcutPressStart: Date?
    @ObservationIgnored private var setupWindowController: SetupWindowController?
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

        transcriptHistoryDays = historyClient.bootstrap(historyRetentionMode, transcriptHistoryDays)

        registerShortcutHandlers()
        registerKeyboardMonitor()
        refreshPermissionStatus()
        startPermissionMonitoring()
        logger.info("AppModel initialized. setupCompleted=\(self.hasCompletedSetup, privacy: .public), model=\(self.selectedModelID, privacy: .public)")
        consoleLog("AppModel initialized. setupCompleted=\(self.hasCompletedSetup), model=\(self.selectedModelID)")

        Task { await appDidLaunch() }
    }

    // MARK: - Computed Properties

    var selectedModelOption: ModelOption? {
        ModelOption(rawValue: selectedModelID)
    }

    var isSelectedModelDownloaded: Bool {
        guard let selectedModelOption else { return false }
        return downloadClient.isModelDownloaded(selectedModelOption)
    }

    var statusTitle: String {
        switch sessionState {
        case .idle:
            return hasCompletedSetup ? "Ready" : "Setup Required"
        case .recording:
            return "REC"
        case let .processing(stage):
            switch stage {
            case .trimming: return "Trimming"
            case .speeding: return "Speeding"
            case .transcribing: return "Transcribing"
            }
        case .error:
            return "Error"
        }
    }

    var menuBarSymbolName: String {
        switch sessionState {
        case .idle: return "waveform.badge.mic"
        case .recording: return "record.circle.fill"
        case let .processing(stage):
            switch stage {
            case .trimming: return "scissors"
            case .speeding: return "figure.run"
            case .transcribing: return "hourglass"
            }
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var currentModelSummary: String {
        guard let selectedModelOption else { return "No model selected" }
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

    var historyDirectoryDisplayPath: String {
        historyClient.historyDirectoryPath()
    }

    // MARK: - Setup

    func changeModelButtonTapped() {
        if isPreviewMode { return }
        beginSetupFlow()
        showSetupWindow()
    }

    // MARK: - Lifecycle

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

    // MARK: - Permissions (runtime)

    func microphonePermissionButtonTapped() async {
        if isPreviewMode {
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            lastError = nil
            return
        }

        let granted = await permissionsClient.requestMicrophonePermission()
        await refreshPermissionStatusAsync()
        logger.info("Microphone permission request resolved. granted=\(granted, privacy: .public), authorized=\(self.microphoneAuthorized, privacy: .public)")
        consoleLog("Microphone permission request resolved. granted=\(granted), authorized=\(self.microphoneAuthorized)")

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

    func accessibilityPermissionButtonTapped() {
        if isPreviewMode {
            accessibilityAuthorized = true
            transientMessage = nil
            return
        }

        Task {
            await permissionsClient.promptForAccessibilityPermission()
            await refreshPermissionStatusAsync()
            logger.info("Accessibility permission prompt shown. authorized=\(self.accessibilityAuthorized, privacy: .public)")
            consoleLog("Accessibility permission prompt shown. authorized=\(self.accessibilityAuthorized)")

            if !accessibilityAuthorized {
                await permissionsClient.openAccessibilityPrivacySettings()
                transientMessage = "Enable Accessibility to allow automatic paste."
            }
        }
    }

    // MARK: - History

    func copyTranscriptHistoryButtonTapped(_ entryID: UUID) {
        guard let entry = transcriptHistoryDays.flatMap(\.entries).first(where: { $0.id == entryID }) else { return }
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
        let opened = historyClient.openHistoryFolder(historyRetentionMode)
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

        guard let audioURL = historyClient.historyAudioURL(audioRelativePath) else {
            transientMessage = "Saved audio file not found."
            return
        }

        NSWorkspace.shared.open(audioURL)
    }

    // MARK: - Deep Links

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

    // MARK: - Push to Talk

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

        let isCurrentlyRecording = await audioClient.isRecording()

        if toggleRecordingIsActive, !isCurrentlyRecording {
            toggleRecordingIsActive = false
        }

        if toggleRecordingIsActive, isCurrentlyRecording {
            toggleRecordingIsActive = false
            ignoreNextShortcutKeyUp = true
            logger.info("Toggle recording stop requested")
            consoleLog("Toggle recording stop requested")
            await stopRecordingAndTranscribe()
            return
        }

        guard !pushToTalkIsActive else { return }

        pushToTalkIsActive = true
        currentShortcutPressStart = now

        if !microphoneAuthorized {
            await microphonePermissionButtonTapped()
            await refreshPermissionStatusAsync()

            guard microphoneAuthorized else {
                sessionState = .error("Microphone permission denied")
                transientMessage = "Enable microphone access to record."
                pushToTalkIsActive = false
                currentShortcutPressStart = nil
                await floatingCapsuleClient.showError("Microphone denied")
                await hideCapsuleAfterDelay()
                return
            }
        }

        do {
            try await audioClient.startRecording { [weak self] level in
                guard let self else { return }
                Task { @MainActor [self, level] in
                    self.recordingLevelDidUpdate(level)
                }
            }

            isAwaitingCancelRecordingConfirmation = false
            sessionState = .recording
            await soundClient.playRecordingStarted()
            await floatingCapsuleClient.showRecording()
            logger.info("Recording started")
            consoleLog("Recording started")
        } catch {
            reportIssue(error)
            sessionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
            pushToTalkIsActive = false
            currentShortcutPressStart = nil
            await floatingCapsuleClient.showError("Recording failed")
            logger.error("Recording failed to start: \(error.localizedDescription, privacy: .public)")
            consoleLog("Recording failed to start: \(error.localizedDescription)")
            await hideCapsuleAfterDelay()
        }
    }

    func pushToTalkKeyUp() async {
        logger.info("Push-to-talk key up")
        consoleLog("Push-to-talk key up")

        if isAwaitingCancelRecordingConfirmation { return }

        if ignoreNextShortcutKeyUp {
            ignoreNextShortcutKeyUp = false
            logger.debug("Ignoring key up after toggle stop")
            return
        }

        guard pushToTalkIsActive else { return }

        pushToTalkIsActive = false

        let isCurrentlyRecording = await audioClient.isRecording()
        guard isCurrentlyRecording else { return }

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

    // MARK: - Private: Recording & Transcription

    private func stopRecordingAndTranscribe() async {
        toggleRecordingIsActive = false
        isAwaitingCancelRecordingConfirmation = false
        sessionState = .processing(.trimming)
        await floatingCapsuleClient.showTrimming()

        do {
            let audioURL = try await audioClient.stopRecording()
            defer { try? FileManager.default.removeItem(at: audioURL) }

            guard let selectedModelOption else {
                throw AppTranscriptionError.pipelineUnavailable
            }

            let audioDuration = transcriptionClient.audioDurationSeconds(audioURL)
            if autoSpeedRate(for: audioDuration) != nil {
                sessionState = .processing(.speeding)
                await floatingCapsuleClient.showSpeeding()
            }

            sessionState = .processing(.transcribing)
            await floatingCapsuleClient.showTranscribing()
            await soundClient.playTranscriptionStarted()
            startTranscriptionProgressTracking(audioDuration: audioDuration)
            let transcriptionStart = now

            let transcript = try await transcriptionClient.transcribe(
                audioURL,
                selectedModelOption,
                transcriptionMode,
                transcriptionMode == .smart ? smartPrompt : nil
            )
            let transcriptionElapsed = now.timeIntervalSince(transcriptionStart)
            updateTranscriptionSpeedEstimate(audioDuration: audioDuration, elapsed: transcriptionElapsed)
            stopTranscriptionProgressTracking(finalProgress: 1)
            await soundClient.playTranscriptionCompleted()

            let pasteResult = await pasteClient.paste(transcript)
            logger.info("Transcription completed. characters=\(transcript.count, privacy: .public), pasteResult=\(String(describing: pasteResult), privacy: .public)")
            consoleLog("Transcription completed. characters=\(transcript.count), pasteResult=\(String(describing: pasteResult))")
            logClient.dumpDebug(
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
            await floatingCapsuleClient.showError("Transcription failed")
            logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            consoleLog("Transcription failed: \(error.localizedDescription)")
        }

        await hideCapsuleAfterDelay()
    }

    // MARK: - Private: Setup Flow

    func beginSetupFlow() {
        guard setupModel == nil else { return }
        let model = SetupModel()
        model.onCompleted = { [weak self] in
            self?.handleSetupCompleted()
        }
        setupModel = model
    }

    private func handleSetupCompleted() {
        hasCompletedSetup = true
        selectedModelID = selectedModelIDStorage
        transientMessage = "Gloam is ready. Quick tap to toggle listening, or hold for push-to-talk."
        setupWindowController?.close()
        setupModel = nil
        logger.info("Setup completed")
        consoleLog("Setup completed")
        Task { await warmModelTask() }
    }

    private func showSetupWindow() {
        if isPreviewMode { return }
        guard let setupModel else { return }

        let controller = SetupWindowController(setupModel: setupModel)
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

    // MARK: - Private: Shortcuts & Keyboard

    private func registerShortcutHandlers() {
        if isPreviewMode { return }
        KeyboardShortcuts.removeHandler(for: .pushToTalk)

        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            Task { await self?.pushToTalkKeyDown() }
        }

        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            Task { await self?.pushToTalkKeyUp() }
        }
    }

    private func registerKeyboardMonitor() {
        if isPreviewMode { return }
        Task {
            await keyboardClient.start { [weak self] keyPress in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.handleMonitoredKeyPress(keyPress)
                }
            }
        }
    }

    private func handleMonitoredKeyPress(_ keyPress: KeyPress) {
        guard case .recording = sessionState else { return }

        Task {
            let isCurrentlyRecording = await audioClient.isRecording()
            guard isCurrentlyRecording else { return }

            if isAwaitingCancelRecordingConfirmation {
                resolveCancelRecordingConfirmation(with: keyPress)
                return
            }

            guard keyPress == .escape else { return }
            presentCancelRecordingConfirmation()
        }
    }

    private func presentCancelRecordingConfirmation() {
        isAwaitingCancelRecordingConfirmation = true
        Task { await floatingCapsuleClient.showCancelConfirmation() }
        logger.info("Recording cancel confirmation shown")
        consoleLog("Recording cancel confirmation shown")
    }

    private func dismissCancelRecordingConfirmation() {
        guard isAwaitingCancelRecordingConfirmation else { return }

        isAwaitingCancelRecordingConfirmation = false
        guard case .recording = sessionState else {
            Task { await floatingCapsuleClient.hide() }
            return
        }

        Task {
            let isCurrentlyRecording = await audioClient.isRecording()
            if isCurrentlyRecording {
                await floatingCapsuleClient.showRecording()
            } else {
                await floatingCapsuleClient.hide()
            }
        }
        logger.info("Recording cancel confirmation dismissed")
        consoleLog("Recording cancel confirmation dismissed")
    }

    private func resolveCancelRecordingConfirmation(with keyPress: KeyPress) {
        switch keyPress {
        case .character("y"):
            cancelRecordingFromConfirmation()
        default:
            dismissCancelRecordingConfirmation()
        }
    }

    private func cancelRecordingFromConfirmation() {
        Task {
            let isCurrentlyRecording = await audioClient.isRecording()
            guard isCurrentlyRecording else {
                isAwaitingCancelRecordingConfirmation = false
                return
            }

            await audioClient.cancelRecording()

            isAwaitingCancelRecordingConfirmation = false
            pushToTalkIsActive = false
            toggleRecordingIsActive = false
            ignoreNextShortcutKeyUp = false
            currentShortcutPressStart = nil
            sessionState = .idle
            transientMessage = "Recording canceled."
            await floatingCapsuleClient.hide()
            logger.info("Recording canceled from keyboard confirmation")
            consoleLog("Recording canceled from keyboard confirmation")
        }
    }

    // MARK: - Private: Permissions

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

    // MARK: - Private: Deep Links

    private func startRecordingFromDeepLink() async {
        guard hasCompletedSetup else {
            transientMessage = "Complete setup before recording."
            beginSetupFlow()
            showSetupWindow()
            return
        }

        let isCurrentlyRecording = await audioClient.isRecording()
        if isCurrentlyRecording || isProcessing { return }

        if !microphoneAuthorized {
            await microphonePermissionButtonTapped()
            await refreshPermissionStatusAsync()
            guard microphoneAuthorized else { return }
        }

        do {
            try await audioClient.startRecording { [weak self] level in
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
            await soundClient.playRecordingStarted()
            await floatingCapsuleClient.showRecording()
            logger.info("Recording started from deep link")
            consoleLog("Recording started from deep link")
        } catch {
            reportIssue(error)
            sessionState = .error(error.localizedDescription)
            lastError = error.localizedDescription
            await floatingCapsuleClient.showError("Recording failed")
            logger.error("Deep link start failed: \(error.localizedDescription, privacy: .public)")
            consoleLog("Deep link start failed: \(error.localizedDescription)")
            await hideCapsuleAfterDelay()
        }
    }

    private func stopRecordingFromDeepLink() async {
        let isCurrentlyRecording = await audioClient.isRecording()
        guard isCurrentlyRecording else { return }
        logger.info("Stopping recording from deep link")
        consoleLog("Stopping recording from deep link")
        await stopRecordingAndTranscribe()
    }

    private func toggleRecordingFromDeepLink() async {
        let isCurrentlyRecording = await audioClient.isRecording()
        if isCurrentlyRecording {
            await stopRecordingFromDeepLink()
        } else {
            await startRecordingFromDeepLink()
        }
    }

    // MARK: - Private: Helpers

    private func recordingLevelDidUpdate(_ level: Double) {
        guard case .recording = sessionState else { return }
        Task { await floatingCapsuleClient.updateLevel(level) }
    }

    private func warmModelTask() async {
        if isPreviewMode { return }
        guard let selectedModelOption else { return }
        logger.info("Warming model: \(selectedModelOption.rawValue, privacy: .public)")
        consoleLog("Warming model: \(selectedModelOption.rawValue)")

        do {
            try await transcriptionClient.prepareModelIfNeeded(selectedModelOption)
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
        await floatingCapsuleClient.hide()

        if case .error = sessionState {
            sessionState = .idle
        }
    }

    private var isProcessing: Bool {
        if case .processing = sessionState { return true }
        return false
    }

    private func autoSpeedRate(for audioDuration: Double) -> Double? {
        switch audioDuration {
        case ..<45: return nil
        case 45..<90: return 1.1
        case 90..<180: return 1.2
        default: return 1.25
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
        logClient.debug("AppModel", message)
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
                await self.floatingCapsuleClient.updateTranscriptionProgress(progress)

                try? await self.clock.sleep(for: .milliseconds(120))
            }
        }
    }

    private func stopTranscriptionProgressTracking(finalProgress: Double? = nil) {
        transcriptionProgressTask?.cancel()
        transcriptionProgressTask = nil

        if let finalProgress {
            Task { await floatingCapsuleClient.updateTranscriptionProgress(finalProgress) }
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
        transcriptHistoryDays = historyClient.appendEntry(
            AppendEntryRequest(
                currentDays: transcriptHistoryDays,
                transcript: transcript,
                modelID: modelID,
                mode: mode,
                audioDuration: audioDuration,
                transcriptionElapsed: transcriptionElapsed,
                pasteResult: pasteResult.rawValue,
                audioRelativePath: audioRelativePath,
                transcriptRelativePath: transcriptRelativePath,
                retentionMode: historyRetentionMode,
                timestamp: now,
                id: uuid()
            )
        )
    }

    private func persistHistoryArtifacts(
        audioURL: URL,
        transcript: String,
        timestamp: Date,
        mode: String,
        modelID: String
    ) -> PersistedArtifacts? {
        historyClient.persistArtifacts(
            PersistArtifactsRequest(
                audioURL: audioURL,
                transcript: transcript,
                timestamp: timestamp,
                mode: mode,
                modelID: modelID,
                retentionMode: historyRetentionMode
            )
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

private enum AppTranscriptionError: LocalizedError {
    case pipelineUnavailable

    var errorDescription: String? {
        switch self {
        case .pipelineUnavailable:
            return "Transcription pipeline is not available."
        }
    }
}

#if DEBUG
extension AppModel {
    static func makePreview(_ configure: (AppModel) -> Void = { _ in }) -> AppModel {
        let model = AppModel(isPreviewMode: true)
        model.hasCompletedSetup = true
        model.selectedModelID = ModelOption.defaultOption.rawValue
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
