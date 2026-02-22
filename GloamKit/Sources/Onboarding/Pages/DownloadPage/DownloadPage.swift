import Shared
import SwiftUI
import UI

struct DownloadPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                symbol: "arrow.down.circle",
                title: "Download Model",
                description: "Download your selected model to get started.",
                layout: .vertical
            )
            .slideIn(active: isAnimating, delay: 0.25)

            if let option = model.selectedModelOption {
                ModelSummaryCard(option: option)
                    .slideIn(active: isAnimating, delay: 0.5)
            }

            if downloadModel.isDownloadingModel || downloadModel.downloadProgress > 0 || !downloadModel.downloadStatus.isEmpty {
                downloadProgressCard
                    .slideIn(active: isAnimating, delay: 0.75)
            }

            if let error = downloadModel.lastError ?? model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { isAnimating = true }
    }

    // MARK: - Subviews

    private var downloadProgressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(downloadModel.downloadStatus.isEmpty ? "Download status" : downloadModel.downloadStatus)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(downloadModel.downloadSummaryText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: downloadModel.downloadProgress)

            if let speedText = downloadModel.downloadSpeedText {
                Text(speedText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

    // MARK: - Computed

    private var downloadModel: ModelDownloadViewModel {
        model.modelDownloadViewModel
    }
}

#Preview("Download - Idle") {
    OnboardingView(model: .makePreview(page: .download))
}

#Preview("Download - In Progress") {
    OnboardingView(model: .makePreview(page: .download) { model in
        model.isDownloadingModel = true
        model.downloadProgress = 0.42
        model.downloadStatus = "Downloading model..."
        model.downloadSpeedText = "18.2 MB/s"
    })
}
