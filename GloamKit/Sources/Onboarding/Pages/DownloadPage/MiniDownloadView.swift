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
        VStack {
            ZStack {
                CircularProgressRing(
                    progress: progressFraction,
                    size: 64,
                    lineWidth: 6
                )

                VStack {
                    Text(percentText)
                        .font(.headline)

                    if let speedText {
                        Text(speedText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 120, height: 144)
        background {
            ZStack {
                if let icon = model.selectedModelOption?.provider.icon {
                    icon
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 64)
                }
            }
        }
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

// MARK: - Previews

@MainActor private func previewModel(state: ModelDownloadState) -> ModelDownloadModel {
    let model = ModelDownloadModel(isPreviewMode: true)
    model.state = state
    return model
}

#Preview("Downloading") {
    MiniDownloadView(
        model: previewModel(state: .downloading(.init(
            fraction: 0.42,
            statusText: "Downloading model...",
            speedText: "18.2 MB/s"
        ))),
        onExpand: {}
    )
}

#Preview("Downloading - Almost Done") {
    MiniDownloadView(
        model: previewModel(state: .downloading(.init(
            fraction: 0.93,
            statusText: "Downloading model...",
            speedText: "24.7 MB/s"
        ))),
        onExpand: {}
    )
}

#Preview("Paused") {
    MiniDownloadView(
        model: previewModel(state: .paused(.init(
            fraction: 0.42,
            statusText: "Download paused"
        ))),
        onExpand: {}
    )
}

#Preview("Just Started") {
    MiniDownloadView(
        model: previewModel(state: .downloading(.init(
            fraction: 0.02,
            statusText: "Downloading model...",
            speedText: "3.1 MB/s"
        ))),
        onExpand: {}
    )
}

#Preview("Not Downloaded") {
    MiniDownloadView(
        model: previewModel(state: .notDownloaded),
        onExpand: {}
    )
}
