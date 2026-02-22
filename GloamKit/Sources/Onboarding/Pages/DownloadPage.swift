import Shared
import SwiftUI
import UI

struct DownloadPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .slideIn(active: isAnimating, delay: 0.25)

            VStack(spacing: 8) {
                Text("Download Model")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("Download your selected model to get started.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .slideIn(active: isAnimating, delay: 0.5)

            modelSummaryCard
                .slideIn(active: isAnimating, delay: 0.75)

            if downloadModel.isDownloadingModel || downloadModel.downloadProgress > 0 || !downloadModel.downloadStatus.isEmpty {
                downloadProgressCard
                    .slideIn(active: isAnimating, delay: 1.0)
            }

            if let error = downloadModel.lastError ?? model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { isAnimating = true }
    }

    private var modelSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let option = model.selectedModelOption {
                HStack(spacing: 10) {
                    Label(option.displayName, systemImage: "cpu")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text(option.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Label(option.descriptor.quantization, systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(option.descriptor.parameters, systemImage: "chart.bar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

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

    private var downloadModel: ModelDownloadViewModel {
        model.modelDownloadViewModel
    }
}

#Preview("Download - Idle") {
    OnboardingPagePreview {
        DownloadPage(model: .makePreview())
    }
}

#Preview("Download - In Progress") {
    OnboardingPagePreview {
        DownloadPage(
            model: .makePreview { model in
                model.isDownloadingModel = true
                model.downloadProgress = 0.42
                model.downloadStatus = "Downloading model..."
                model.downloadSpeedText = "18.2 MB/s"
            }
        )
    }
}
