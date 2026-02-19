import Foundation
import Observation

@MainActor
@Observable
public final class RecordingSessionModel {
    public enum SessionState: Equatable, Sendable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    public var sessionState: SessionState = .idle
    public var transientMessage: String?
    public var lastError: String?
    public var pushToTalkIsActive = false
    public var toggleRecordingIsActive = false
    public var isAwaitingCancelRecordingConfirmation = false
    public var ignoreNextShortcutKeyUp = false
    public var toggleActivationThresholdSeconds = 2.0

    private var currentShortcutPressStart: Date?

    public init() {}

    public func pushToTalkKeyDown(hasCompletedSetup: Bool, isRecording: Bool, at now: Date = Date()) -> RecordingTransition {
        if isAwaitingCancelRecordingConfirmation {
            isAwaitingCancelRecordingConfirmation = false
        }

        guard hasCompletedSetup else {
            transientMessage = "Complete setup before recording."
            return .openSetup
        }

        if toggleRecordingIsActive, isRecording {
            toggleRecordingIsActive = false
            ignoreNextShortcutKeyUp = true
            return .stopRecording
        }

        guard !pushToTalkIsActive else {
            return .none
        }

        pushToTalkIsActive = true
        currentShortcutPressStart = now

        return .startRecording
    }

    public func pushToTalkKeyUp(isRecording: Bool, at now: Date = Date()) -> RecordingTransition {
        if isAwaitingCancelRecordingConfirmation {
            return .none
        }

        if ignoreNextShortcutKeyUp {
            ignoreNextShortcutKeyUp = false
            return .none
        }

        guard pushToTalkIsActive else {
            return .none
        }

        pushToTalkIsActive = false

        guard isRecording else {
            return .none
        }

        let holdDuration = now.timeIntervalSince(currentShortcutPressStart ?? now)
        currentShortcutPressStart = nil

        if holdDuration < toggleActivationThresholdSeconds {
            toggleRecordingIsActive = true
            transientMessage = "Listening... press shortcut again to stop."
            return .waitForToggleStop
        }

        return .stopRecording
    }

    public func presentCancelRecordingConfirmation() {
        isAwaitingCancelRecordingConfirmation = true
    }

    public func resolveCancelRecordingConfirmation(pressedY: Bool) -> RecordingTransition {
        if !isAwaitingCancelRecordingConfirmation {
            return .none
        }

        isAwaitingCancelRecordingConfirmation = false
        if pressedY {
            resetAfterCancel()
            return .cancelRecording
        }

        return .dismissCancelConfirmation
    }

    public func markRecordingStarted() {
        sessionState = .recording
        lastError = nil
    }

    public func markTranscribing() {
        sessionState = .transcribing
        toggleRecordingIsActive = false
    }

    public func markIdle() {
        sessionState = .idle
    }

    public func markError(_ message: String) {
        lastError = message
        transientMessage = "Transcription failed."
        sessionState = .error(message)
    }

    private func resetAfterCancel() {
        pushToTalkIsActive = false
        toggleRecordingIsActive = false
        ignoreNextShortcutKeyUp = false
        currentShortcutPressStart = nil
        sessionState = .idle
        transientMessage = "Recording canceled."
    }
}

public enum RecordingTransition: Sendable, Equatable {
    case none
    case openSetup
    case startRecording
    case waitForToggleStop
    case stopRecording
    case cancelRecording
    case dismissCancelConfirmation
}
