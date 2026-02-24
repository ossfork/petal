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
        switch downloadModel.state {
        case .downloaded:
            DownloadCompleteCard(modelDirectoryURL: downloadModel.modelDirectoryURL)
        case let .downloading(progress):
            DownloadProgressCard(
                progress: progress.fraction,
                speedText: progress.speedText,
                isPaused: false,
                onPause: { downloadModel.pauseDownload() },
                onResume: {},
                onCancel: { downloadModel.cancelDownload() }
            )
        case let .paused(progress):
            DownloadProgressCard(
                progress: progress.fraction,
                speedText: progress.speedText,
                isPaused: true,
                onPause: {},
                onResume: { Task { await downloadModel.resumeDownload() } },
                onCancel: { downloadModel.cancelDownload() }
            )
        case .preparing:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .center)
        case .notDownloaded, .failed:
            EmptyView()
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

    private var downloadModel: ModelDownloadModel {
        model.modelDownloadViewModel
    }
}

#Preview("Download - Idle") {
    OnboardingView(model: .makePreview(page: .download))
}

#Preview("Download - In Progress") {
    OnboardingView(model: .makePreview(page: .download) { model in
        model.modelDownloadViewModel.state = .downloading(.init(
            fraction: 0.42,
            statusText: "Downloading model...",
            speedText: "18.2 MB/s"
        ))
    })
}

#Preview("Download - Paused") {
    OnboardingView(model: .makePreview(page: .download) { model in
        model.modelDownloadViewModel.state = .paused(.init(
            fraction: 0.42,
            statusText: "Download paused"
        ))
    })
}

#Preview("Download - Complete") {
    OnboardingView(model: .makePreview(page: .download) { model in
        model.modelDownloadViewModel.state = .downloaded
    })
}
