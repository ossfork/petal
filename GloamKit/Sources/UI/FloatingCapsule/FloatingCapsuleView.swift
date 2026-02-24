import SwiftUI

public struct FloatingCapsuleView: View {
    @Bindable var state: FloatingCapsuleState

    public init(state: FloatingCapsuleState) {
        self.state = state
    }

    public var body: some View {
        Group {
            switch self.state.phase {
            case .hidden:
                Color.clear
            case .recording:
                recording
            case .confirmCancel:
                confirmCancel
            case .trimming:
                trimming
            case .speeding:
                speeding
            case .transcribing:
                transcribing
            case .refining:
                RefiningCapsuleContent()
            case .error:
                error
            }
        }
        .frame(
            minWidth: CapsuleStyle.minWidth, maxWidth: CapsuleStyle.maxWidth,
            minHeight: CapsuleStyle.height, maxHeight: CapsuleStyle.height
        )
        .animation(.snappy(duration: 0.18), value: self.state.phase)
    }

    // MARK: - Phase content

    private var recording: some View {
        HStack(spacing: CapsuleStyle.hStackSpacing) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            Text("REC")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)

            RecordingBars(level: self.state.level)
        }
        .floatingCapsuleChrome()
    }

    private var confirmCancel: some View {
        HStack(spacing: 6) {
            Image(systemName: "escape")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            (
                Text("Cancel recording?  ")
                    + Text("Y").foregroundColor(.red)
                    + Text(" / N")
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
        .floatingCapsuleChrome()
    }

    private var trimming: some View {
        HStack(spacing: CapsuleStyle.hStackSpacing) {
            Image(systemName: "scissors")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)

            Text("Trimming silence")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome()
    }

    private var speeding: some View {
        HStack(spacing: CapsuleStyle.hStackSpacing) {
            Image(systemName: "figure.run")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.teal)

            Text("Speeding audio")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.teal)
        }
        .floatingCapsuleChrome()
    }

    private var transcribing: some View {
        HStack(spacing: CapsuleStyle.hStackSpacing) {
            CircularProgressRing(progress: self.state.transcriptionProgress)

            Text(self.transcribingLabel)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome()
    }

    private var error: some View {
        HStack(spacing: CapsuleStyle.hStackSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption2.weight(.bold))

            Text("Error")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome()
    }

    private var transcribingLabel: String {
        let percent = Int((state.transcriptionProgress * 100).rounded())
        return "Transcribing \(String(format: "%3d", percent))%"
    }
}

// MARK: - Previews

@MainActor
private func makePreviewState(
    phase: FloatingCapsuleState.Phase,
    level: Double = 0.58,
    progress: Double = 0.47
) -> FloatingCapsuleState {
    let state = FloatingCapsuleState()
    state.phase = phase
    state.level = level
    state.transcriptionProgress = progress
    return state
}

@MainActor
private func capsulePreview(_ state: FloatingCapsuleState) -> some View {
    FloatingCapsuleView(state: state)
        .padding(24)
        .frame(width: 340, height: 110)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
}

#Preview("Recording") {
    capsulePreview(makePreviewState(phase: .recording, level: 0.72))
}

#Preview("Confirm Cancel") {
    capsulePreview(makePreviewState(phase: .confirmCancel))
}

#Preview("Trimming") {
    capsulePreview(makePreviewState(phase: .trimming))
}

#Preview("Transcribing") {
    capsulePreview(makePreviewState(phase: .transcribing, progress: 0.64))
}

#Preview("Refining") {
    capsulePreview(makePreviewState(phase: .refining))
}

#Preview("Error") {
    capsulePreview(makePreviewState(phase: .error("Preview")))
}
