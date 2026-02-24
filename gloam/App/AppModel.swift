import AppKit
import AudioClient
import class SwiftUI.NSHostingView
import FloatingCapsuleClient
import Foundation
import HistoryClient
import IssueReporting
import KeyboardClient
import KeyboardShortcuts
import LogClient
import Observation
import ModelDownloadFeature
import Onboarding
import os
import PasteClient
import PermissionsClient
import Sauce
import Shared
import SoundClient
import TranscriptionClient
import UserNotifications
import WindowClient

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

    @ObservationIgnored @Shared(.hasCompletedSetup) var hasCompletedSetup = false
    @ObservationIgnored @Shared(.transcriptionMode) var transcriptionMode: TranscriptionMode = .verbatim
    @ObservationIgnored @Shared(.smartPrompt) var smartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said."
    @ObservationIgnored @Shared(.trimSilenceEnabled) var trimSilenceEnabled = true
    @ObservationIgnored @Shared(.autoSpeedEnabled) var autoSpeedEnabled = true
    @ObservationIgnored @Shared(.compressHistoryAudio) var compressHistoryAudio = false
    @ObservationIgnored @Shared(.historyRetentionMode) var historyRetentionMode: HistoryRetentionMode = .both
    @ObservationIgnored @Shared(.transcriptHistoryDays) var transcriptHistoryDays: [TranscriptHistoryDay] = []

    let modelDownloadViewModel: ModelDownloadModel

    var selectedModelID: String {
        get { modelDownloadViewModel.selectedModelID }
        set {
            modelDownloadViewModel.$selectedModelID.withLock { $0 = newValue }
            selectedModelDidChange()
        }
    }

    var sessionState: SessionState = .idle
    var lastError: String?
    var transientMessage: String?
    var microphonePermissionState: MicrophonePermissionState = .notDetermined
    var microphoneAuthorized = false
    var accessibilityAuthorized = false

    var onboardingModel: OnboardingModel?

    @ObservationIgnored @Dependency(\.continuousClock) private var clock
    @ObservationIgnored @Dependency(\.date.now) private var now
    @ObservationIgnored @Dependency(\.uuid) private var uuid
    @ObservationIgnored @Dependency(\.transcriptionClient) private var transcriptionClient
    @ObservationIgnored @Dependency(\.pasteClient) private var pasteClient
    @ObservationIgnored @Dependency(\.permissionsClient) private var permissionsClient
    @ObservationIgnored @Dependency(\.audioClient) private var audioClient
    @ObservationIgnored @Dependency(\.keyboardClient) private var keyboardClient
    @ObservationIgnored @Dependency(\.floatingCapsuleClient) private var floatingCapsuleClient
    @ObservationIgnored @Dependency(\.soundClient) private var soundClient
    @ObservationIgnored @Dependency(\.historyClient) private var historyClient
    @ObservationIgnored @Dependency(\.logClient) private var logClient
    @ObservationIgnored @Dependency(\.windowClient) private var windowClient
    @ObservationIgnored private let logger = Logger(subsystem: "com.optimalapps.gloam", category: "AppModel")

    @ObservationIgnored private let isPreviewMode: Bool

    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var pushToTalkIsActive = false
    @ObservationIgnored private var toggleRecordingIsActive = false
    @ObservationIgnored private var isAwaitingCancelRecordingConfirmation = false
    @ObservationIgnored private var ignoreNextShortcutKeyUp = false
    @ObservationIgnored private var currentShortcutPressStart: Date?
    @ObservationIgnored private var transcriptionProgressTask: Task<Void, Never>?
    @ObservationIgnored private var permissionMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var estimatedTranscriptionRTF = 2.2
    @ObservationIgnored private let toggleActivationThresholdSeconds = 2.0

    nonisolated private static var isRunningInSwiftUIPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    init(isPreviewMode: Bool = AppModel.isRunningInSwiftUIPreview) {
        self.isPreviewMode = isPreviewMode
        modelDownloadViewModel = ModelDownloadModel(isPreviewMode: isPreviewMode)

        if isPreviewMode {
            $hasCompletedSetup.withLock { $0 = true }
            selectedModelID = ModelOption.defaultOption.rawValue
            microphonePermissionState = .authorized
            microphoneAuthorized = true
            accessibilityAuthorized = true
            return
        }

        $transcriptHistoryDays.withLock { $0 = historyClient.bootstrap(historyRetentionMode, $0) }

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

    var availableTranscriptionModes: [TranscriptionMode] {
        selectedModelOption?.supportedTranscriptionModes ?? [.verbatim]
    }

    var selectedModelSupportsSmartTranscription: Bool {
        selectedModelOption?.supportsSmartTranscription ?? false
    }

    var isSelectedModelDownloaded: Bool {
        modelDownloadViewModel.isSelectedModelDownloaded
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
        let modifiers = shortcut.modifiers.description
        let key = Sauce.shared.key(for: shortcut.carbonKeyCode)?.rawValue.uppercased() ?? "?"
        return "Current: \(modifiers)\(key)"
    }

    var shortcutUsageText: String {
        "Quick press to toggle recording. Hold for \(Int(toggleActivationThresholdSeconds)) seconds or more for push-to-talk."
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

    func selectedModelDidChange() {
        modelDownloadViewModel.selectedModelChanged()
        let normalizedMode = normalizedTranscriptionMode(transcriptionMode)
        if transcriptionMode != normalizedMode {
            $transcriptionMode.withLock { $0 = normalizedMode }
        }
    }

    func changeModelButtonTapped() {
        if isPreviewMode { return }
        beginOnboardingFlow()
        showOnboardingWindow()
    }

    func openSettingsWindow() {
        if isPreviewMode { return }
        showSettingsWindow()
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

        $hasCompletedSetup.withLock { $0 = false }
        beginOnboardingFlow()
        try? await clock.sleep(for: .milliseconds(150))
        showOnboardingWindow()
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
            lastError = "Turn on microphone access in System Settings, then return to Gloam."
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
                transientMessage = "Turn on Accessibility in System Settings to continue using Gloam."
            }
        }
    }

    // MARK: - History

    func copyTranscriptHistoryButtonTapped(_ entryID: UUID) {
        guard let entry = transcriptHistoryDays.flatMap(\.entries).first(where: { $0.id == entryID }) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formattedHistoryEntry(entry), forType: .string)
        transientMessage = "Copied to clipboard."
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
            transientMessage = "History is turned off."
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
            transientMessage = "Complete setup to start recording."
            beginOnboardingFlow()
            showOnboardingWindow()
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
                transientMessage = "Turn on microphone access to record."
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
            transientMessage = "Listening — tap your shortcut to stop."
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
            let mode = normalizedTranscriptionMode(transcriptionMode)
            if transcriptionMode != mode {
                $transcriptionMode.withLock { $0 = mode }
            }

            let transcript = try await transcriptionClient.transcribe(
                audioURL,
                selectedModelOption,
                mode,
                mode == .smart ? smartPrompt : nil
            )
            let transcriptionElapsed = now.timeIntervalSince(transcriptionStart)
            updateTranscriptionSpeedEstimate(audioDuration: audioDuration, elapsed: transcriptionElapsed)
            stopTranscriptionProgressTracking(finalProgress: 1)

            let isEmptyTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if isEmptyTranscript {
                await soundClient.playTranscriptionNoResult()
                transientMessage = "No speech detected."
                logger.info("Empty transcription result — no speech detected")
                consoleLog("Empty transcription result — no speech detected")

                let persistedPaths = await persistHistoryArtifacts(
                    audioURL: audioURL,
                    transcript: transcript,
                    timestamp: transcriptionStart,
                    mode: mode.rawValue,
                    modelID: selectedModelOption.rawValue
                )

                appendTranscriptHistory(
                    transcript: transcript,
                    modelID: selectedModelOption.rawValue,
                    mode: mode.rawValue,
                    audioDuration: audioDuration,
                    transcriptionElapsed: transcriptionElapsed,
                    pasteResult: .skipped,
                    audioRelativePath: persistedPaths?.audioRelativePath,
                    transcriptRelativePath: persistedPaths?.transcriptRelativePath
                )
            } else {
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

                let persistedPaths = await persistHistoryArtifacts(
                    audioURL: audioURL,
                    transcript: transcript,
                    timestamp: transcriptionStart,
                    mode: mode.rawValue,
                    modelID: selectedModelOption.rawValue
                )

                appendTranscriptHistory(
                    transcript: transcript,
                    modelID: selectedModelOption.rawValue,
                    mode: mode.rawValue,
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
                    transientMessage = "Accessibility access is needed to paste. Turn it on in System Settings, then try again."
                    await postPasteFallbackNotification()
                case .skipped:
                    break
                }
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

    func beginOnboardingFlow() {
        guard onboardingModel == nil else { return }
        let model = OnboardingModel(downloadViewModel: modelDownloadViewModel)
        model.onCompleted = { [weak self] in
            self?.handleOnboardingCompleted()
        }
        onboardingModel = model
    }

    private func handleOnboardingCompleted() {
        selectedModelDidChange()
        $hasCompletedSetup.withLock { $0 = true }
        transientMessage = "You're all set. Tap your shortcut to start, or hold for push-to-talk."
        Task { await windowClient.close(WindowConfig.onboarding.id) }
        onboardingModel = nil
        logger.info("Onboarding completed")
        consoleLog("Onboarding completed")
        Task { await warmModelTask() }
    }

    private func showOnboardingWindow() {
        if isPreviewMode { return }
        guard let onboardingModel else { return }

        Task {
            await windowClient.closeAll(WindowConfig.onboarding.id)
            await windowClient.show(.onboarding, {
                SwiftUI.NSHostingView(rootView: OnboardingView(model: onboardingModel))
            }, {})
        }
    }

    private func showSettingsWindow() {
        if isPreviewMode { return }
        let settingsViewModel = SettingsViewModel(appModel: self)
        NSApp.setActivationPolicy(.regular)
        Task {
            await windowClient.closeAll(WindowConfig.settings.id)
            await windowClient.show(.settings, {
                SwiftUI.NSHostingView(rootView: SettingsView(viewModel: settingsViewModel))
            }, {
                NSApp.setActivationPolicy(.accessory)
            })
        }
    }

    // MARK: - Private: Shortcuts & Keyboard

    private func registerShortcutHandlers() {
        if isPreviewMode { return }
        KeyboardShortcuts.removeAllHandlers()

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
                MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.shouldConsumeKeyPress(keyPress)
                }
            }
        }
    }

    /// Decides synchronously whether to swallow the event, then dispatches async handling.
    private func shouldConsumeKeyPress(_ keyPress: KeyPress) -> Bool {
        guard case .recording = sessionState else { return false }

        if isAwaitingCancelRecordingConfirmation {
            Task { await handleConfirmationKeyPress(keyPress) }
            return true
        }

        guard keyPress == .escape else { return false }
        Task { await handleEscapeDuringRecording() }
        return true
    }

    private func handleConfirmationKeyPress(_ keyPress: KeyPress) async {
        let isCurrentlyRecording = await audioClient.isRecording()
        guard isCurrentlyRecording else { return }
        resolveCancelRecordingConfirmation(with: keyPress)
    }

    private func handleEscapeDuringRecording() async {
        let isCurrentlyRecording = await audioClient.isRecording()
        guard isCurrentlyRecording else { return }
        presentCancelRecordingConfirmation()
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
            transientMessage = "Recording cancelled."
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
            transientMessage = "Complete setup to start recording."
            beginOnboardingFlow()
            showOnboardingWindow()
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

    private func normalizedTranscriptionMode(_ mode: TranscriptionMode) -> TranscriptionMode {
        guard let selectedModelOption else { return mode }
        return selectedModelOption.supportsTranscriptionMode(mode) ? mode : .verbatim
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

        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let content = UNMutableNotificationContent()
        content.title = "Gloam"
        content.body = "Transcript copied to clipboard. Press Command-V to paste."

        let request = UNNotificationRequest(
            identifier: uuid().uuidString,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
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
        let entry = historyClient.appendEntry(
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
        $transcriptHistoryDays.withLock { $0 = entry }
    }

    private func persistHistoryArtifacts(
        audioURL: URL,
        transcript: String,
        timestamp: Date,
        mode: String,
        modelID: String
    ) async -> PersistedArtifacts? {
        await historyClient.persistArtifacts(
            PersistArtifactsRequest(
                audioURL: audioURL,
                transcript: transcript,
                timestamp: timestamp,
                mode: mode,
                modelID: modelID,
                retentionMode: historyRetentionMode,
                compressAudio: compressHistoryAudio
            )
        )
    }

    private func formattedHistoryEntry(_ entry: TranscriptHistoryEntry) -> String {
        entry.transcript
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
        model.$hasCompletedSetup.withLock { $0 = true }
        model.selectedModelID = ModelOption.defaultOption.rawValue
        model.sessionState = .idle
        model.lastError = nil
        model.transientMessage = nil
        model.$transcriptHistoryDays.withLock { $0 = [] }
        model.microphonePermissionState = .authorized
        model.microphoneAuthorized = true
        model.accessibilityAuthorized = true
        configure(model)
        return model
    }
}
#endif
