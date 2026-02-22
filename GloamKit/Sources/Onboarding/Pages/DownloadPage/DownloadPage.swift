import Assets
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
                description: "This may take a few minutes depending on your connection.",
                layout: .vertical
            )
            .slideIn(active: isAnimating, delay: 0.25)

            if let option = model.selectedModelOption {
                downloadCard(option: option)
                    .slideIn(active: isAnimating, delay: 0.5)
            }

            if let error = downloadModel.lastError ?? model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .onAppear { isAnimating = true }
    }

    // MARK: - Subviews

    private func downloadCard(option: ModelOption) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image.appIcon
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.displayName)
                        .font(.headline)

                    Text(option.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(option.sizeLabel + " · " + option.descriptor.parameters, systemImage: "internaldrive")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                if downloadModel.downloadProgress >= 1, !downloadModel.isDownloadingModel {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            }

            if downloadModel.isDownloadingModel || downloadModel.downloadProgress > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: downloadModel.downloadProgress)
                        .tint(downloadModel.downloadProgress >= 1 ? .green : .white)

                    HStack {
                        Text(downloadModel.downloadStatus.isEmpty ? "Preparing..." : downloadModel.downloadStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if downloadModel.isDownloadingModel {
                            Text(downloadModel.downloadSummaryText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
            animated: downloadModel.isDownloadingModel,
            duration: 1.5,
            colors: [.white.opacity(0.0), .white.opacity(0.7), .white.opacity(0.0)]
        )
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
