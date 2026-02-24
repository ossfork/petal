import ModelDownloadFeature
import Shared
import SwiftUI
import UI

public struct MiniDownloadView: View {
    @Bindable var model: ModelDownloadModel
    var onExpand: () -> Void

    public init(model: ModelDownloadModel, onExpand: @escaping () -> Void) {
        self.model = model
        self.onExpand = onExpand
    }

    public var body: some View {
        VStack(spacing: 8) {
            CircularProgressRing(progress: progressFraction, size: 56, lineWidth: 4)

            Text(percentText)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)

            if let speedText {
                Text(speedText)
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 120)
        .overlay(alignment: .topTrailing) {
            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Expand to full window")
            .padding(6)
        }
    }

    // MARK: - Computed

    private var progressFraction: Double {
        model.state.progress?.fraction ?? 0
    }

    private var percentText: String {
        let percent = Int((progressFraction * 100).rounded())
        return "\(percent)%"
    }

    private var speedText: String? {
        model.state.progress?.speedText
    }
}
