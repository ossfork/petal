import SwiftUI

struct FloatingCapsuleView: View {
    @Bindable var state: FloatingCapsuleState

    var body: some View {
        Group {
            switch state.phase {
            case .hidden:
                Color.clear
            case .recording:
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)

                    Text("REC")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    RecordingBars(level: state.level)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            case .confirmCancel:
                HStack(spacing: 6) {
                    Image(systemName: "escape")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    (
                        Text("Cancel recording?  ")
                        + Text("Y").foregroundColor(.red)
                        + Text(" / N")
                    )
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            case .transcribing:
                HStack(spacing: 8) {
                    CircularProgressRing(progress: state.transcriptionProgress)

                    Text(transcribingLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            case .error:
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 10, weight: .bold))

                    Text("Error")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(width: 220, height: 52)
        .animation(.snappy(duration: 0.18), value: state.phase)
    }

    private var transcribingLabel: String {
        let percent = Int((state.transcriptionProgress * 100).rounded())
        return "Transcribing \(String(format: "%3d", percent))%"
    }
}

private struct RecordingBars: View {
    let level: Double

    private let pattern: [CGFloat] = [0.22, 0.44, 0.76, 1.0, 0.76, 0.44, 0.22]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(pattern.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.red.opacity(0.85))
                    .frame(width: 2.8, height: barHeight(index: index, base: value))
            }
        }
        .frame(height: 16)
        .animation(.linear(duration: 0.1), value: level)
    }

    private func barHeight(index: Int, base: CGFloat) -> CGFloat {
        let clamped = max(0.03, min(1, level))
        let scale = CGFloat(clamped) * 12
        return 4 + (scale * base)
    }
}

private struct CircularProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.28), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .animation(.linear(duration: 0.15), value: progress)
    }
}

#if DEBUG
@MainActor
private extension FloatingCapsuleState {
    static func makePreview(phase: Phase, level: Double = 0, transcriptionProgress: Double = 0) -> FloatingCapsuleState {
        let state = FloatingCapsuleState()
        state.phase = phase
        state.level = level
        state.transcriptionProgress = transcriptionProgress
        return state
    }
}

#Preview("Recording") {
    FloatingCapsuleView(state: .makePreview(phase: .recording, level: 0.76))
        .padding()
        .background(Color.black.opacity(0.08))
}

#Preview("Transcribing") {
    FloatingCapsuleView(state: .makePreview(phase: .transcribing, transcriptionProgress: 0.61))
        .padding()
        .background(Color.black.opacity(0.08))
}

#Preview("Cancel Confirmation") {
    FloatingCapsuleView(state: .makePreview(phase: .confirmCancel))
        .padding()
        .background(Color.black.opacity(0.08))
}

#Preview("Error") {
    FloatingCapsuleView(state: .makePreview(phase: .error("Mic denied")))
        .padding()
        .background(Color.black.opacity(0.08))
}
#endif
