import ModelDownloadFeature
import Shared
import SwiftUI
import UI

struct DownloadPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
                .slideIn(active: isAnimating, delay: 0.25)

            if let option = downloadModel.selectedModelOption {
                modelInfo(option)
                    .slideIn(active: isAnimating, delay: 0.4)

                downloadContent
                    .slideIn(active: isAnimating, delay: 0.5)
            }

            errorText

            Spacer()
        }
        .onAppear { isAnimating = true }
    }

    // MARK: - Subviews

    private var header: some View {
        OnboardingHeader(
            symbol: "arrow.down.circle",
            title: "Download Model",
            description: "This may take a few minutes depending on your connection.",
            layout: .vertical
        )
    }

    private func modelInfo(_ option: ModelOption) -> some View {
        HStack(spacing: 14) {
            ModelInfoRow(option: option)
            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var downloadContent: some View {
        if isComplete {
            DownloadCompleteCard(modelDirectoryURL: downloadModel.modelDirectoryURL)
        } else if downloadModel.isDownloadingModel || downloadModel.isPaused {
            DownloadProgressCard(
                progress: downloadModel.downloadProgress,
                speedText: downloadModel.downloadSpeedText,
                isPaused: downloadModel.isPaused,
                onPause: { downloadModel.pauseDownload() },
                onResume: { Task { await downloadModel.resumeDownload() } },
                onCancel: { downloadModel.cancelDownload() }
            )
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let error = downloadModel.lastError ?? model.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Computed

    private var isComplete: Bool {
        downloadModel.downloadProgress >= 1 && !downloadModel.isDownloadingModel && !downloadModel.isPaused
    }

    private var downloadModel: ModelDownloadModel {
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

#Preview("Download - Paused") {
    OnboardingView(model: .makePreview(page: .download) { model in
        model.isPaused = true
        model.downloadProgress = 0.42
        model.downloadStatus = "Download paused"
    })
}

#Preview("Download - Complete") {
    OnboardingView(model: .makePreview(page: .download) { model in
        model.downloadProgress = 1.0
        model.downloadStatus = "Download complete"
    })
}
