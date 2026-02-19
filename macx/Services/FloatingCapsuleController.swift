import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class FloatingCapsuleState {
    enum Phase: Equatable {
        case hidden
        case recording
        case confirmCancel
        case trimming
        case speeding
        case transcribing
        case error(String)
    }

    var phase: Phase = .hidden
    var level: Double = 0
    var transcriptionProgress: Double = 0
}

@MainActor
final class FloatingCapsuleController {
    let state = FloatingCapsuleState()

    private let panel: NSPanel

    init() {
        let contentView = FloatingCapsuleView(state: state)
        let hostingController = NSHostingController(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.contentViewController = hostingController
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.panel = panel
    }

    func showRecording() {
        state.phase = .recording
        showWindowIfNeeded()
    }

    func updateLevel(_ level: Double) {
        state.level = level
    }

    func showTrimming() {
        state.phase = .trimming
        showWindowIfNeeded()
    }

    func showSpeeding() {
        state.phase = .speeding
        showWindowIfNeeded()
    }

    func showTranscribing() {
        state.transcriptionProgress = 0
        state.phase = .transcribing
        showWindowIfNeeded()
    }

    func updateTranscriptionProgress(_ progress: Double) {
        let clamped = min(max(progress, 0), 1)
        state.transcriptionProgress = max(state.transcriptionProgress, clamped)
    }

    func showCancelConfirmation() {
        state.phase = .confirmCancel
        showWindowIfNeeded()
    }

    func showError(_ message: String) {
        state.phase = .error(message)
        showWindowIfNeeded()
    }

    func hide() {
        state.phase = .hidden
        state.level = 0
        state.transcriptionProgress = 0
        panel.orderOut(nil)
    }

    private func showWindowIfNeeded() {
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panel.frame.width / 2
        let y = visibleFrame.minY + 36
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
