import Assets
import SwiftUI
import UI

struct DownloadProgressCard: View {
    let modelIcon: Image
    let modelName: String
    let modelSize: String?
    let progress: Double
    let speedText: String?
    let isPaused: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                modelIcon
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(modelName)
                    .font(.headline)

                Spacer()

                if let modelSize {
                    Text(modelSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(percentText)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .intelligenceGradient()

                Spacer()

                controlButtons
            }

            ZStack(alignment: .top) {
                // Glow shadow below the bar
                AnimatedIntelligenceBar(progress: progress)
                    .frame(height: 8)
                    .blur(radius: 10)
                    .opacity(isPaused ? 0.15 : 0.4)
                    .offset(y: 4)

                AnimatedIntelligenceBar(progress: progress)
                    .frame(height: 8)
            }

            HStack {
                if isPaused {
                    Text("Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let speedText {
                    Text(speedText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
        .runningBorder(
            radius: 16,
            lineWidth: 1,
            animated: !isPaused,
            duration: 1.5,
            colors: [.white.opacity(0.0), .white.opacity(0.7), .white.opacity(0.0)]
        )
    }

    // MARK: - Subviews

    private var controlButtons: some View {
        HStack(spacing: 8) {
            Button(action: isPaused ? onResume : onPause) {
                Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Computed

    private var percentText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

#Preview("In Progress") {
    DownloadProgressCard(
        modelIcon: .qwen,
        modelName: "Qwen3 ASR 0.6B (4-bit)",
        modelSize: "~1.2 GB",
        progress: 0.42,
        speedText: "18.2 MB/s",
        isPaused: false,
        onPause: {},
        onResume: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 400)
}

#Preview("Paused") {
    DownloadProgressCard(
        modelIcon: .qwen,
        modelName: "Qwen3 ASR 0.6B (4-bit)",
        modelSize: "~1.2 GB",
        progress: 0.42,
        speedText: nil,
        isPaused: true,
        onPause: {},
        onResume: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 400)
}
