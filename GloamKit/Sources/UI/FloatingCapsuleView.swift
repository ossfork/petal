import Observation
import SwiftUI

@MainActor
@Observable
public final class FloatingCapsuleState {
    public enum Phase: Equatable {
        case hidden
        case recording
        case confirmCancel
        case trimming
        case speeding
        case transcribing
        case refining
        case error(String)
    }

    public var phase: Phase = .hidden
    public var level: Double = 0
    public var transcriptionProgress: Double = 0

    public init() {}
}

public struct FloatingCapsuleView: View {
    @Bindable var state: FloatingCapsuleState

    public init(state: FloatingCapsuleState) {
        self.state = state
    }

    public var body: some View {
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
                .floatingCapsuleChrome()
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
                .floatingCapsuleChrome()
            case .trimming:
                HStack(spacing: 8) {
                    Image(systemName: "scissors")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text("Trimming silence")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .floatingCapsuleChrome()
            case .speeding:
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.teal)

                    Text("Speeding audio")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.teal)
                }
                .floatingCapsuleChrome()
            case .transcribing:
                HStack(spacing: 8) {
                    CircularProgressRing(progress: state.transcriptionProgress)

                    Text(transcribingLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .floatingCapsuleChrome()
            case .refining:
                RefiningCapsuleContent()
            case .error:
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 10, weight: .bold))

                    Text("Error")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .floatingCapsuleChrome()
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

private extension View {
    func floatingCapsuleChrome() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct RecordingBars: View {
    let level: Double

    private let pattern: [CGFloat] = [0.22, 0.44, 0.76, 1.0, 0.76, 0.44, 0.22]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(pattern.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.red.opacity(0.85))
                    .frame(width: 2.8, height: barHeight(base: value))
            }
        }
        .frame(height: 16)
        .animation(.linear(duration: 0.1), value: level)
    }

    private func barHeight(base: CGFloat) -> CGFloat {
        let clamped = max(0.03, min(1, level))
        let scale = CGFloat(clamped) * 12
        return 4 + (scale * base)
    }
}

public struct CircularProgressRing: View {
    let progress: Double
    var size: CGFloat
    var lineWidth: CGFloat

    public init(progress: Double, size: CGFloat = 16, lineWidth: CGFloat = 2.5) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.28), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.15), value: progress)
    }
}

private struct RefiningCapsuleContent: View {
    @State private var rotation: Double = 0

    private let gradientColors: [Color] = [
        .orange,
        .pink,
        .purple,
        .blue,
        .teal,
        .green,
        .yellow,
        .orange,
    ]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.purple)

            Text("Refining")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        startAngle: .degrees(rotation),
                        endAngle: .degrees(rotation + 360)
                    ),
                    lineWidth: 2
                )
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

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
        .frame(width: 280, height: 110)
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
