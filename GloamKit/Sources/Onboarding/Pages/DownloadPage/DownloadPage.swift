import Assets
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
                downloadContent(option)
                    .slideIn(active: isAnimating, delay: 0.4)
            }

            errorText

            Spacer()
        }
        .onAppear { isAnimating = true }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            OnboardingHeader(
                symbol: selectedModelRequiresDownload ? "arrow.down.circle" : "checkmark.circle",
                title: selectedModelRequiresDownload ? "Download Model" : "Model Ready",
                description: selectedModelRequiresDownload
                    ? "This may take a few minutes depending on your connection."
                    : "This model uses Apple's built-in Speech framework and is ready instantly.",
                layout: .vertical
            )

            Spacer()
        }
        .overlay(alignment: .topTrailing) {
            if downloadModel.state.isActive || downloadModel.state.isPaused {
                Button {
                    model.minimizeToMiniWindow()
                } label: {
                    Image(systemName: "rectangle.inset.topright.filled")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Minimize to mini window")
            }
        }
    }

    @ViewBuilder
    private func downloadContent(_ option: ModelOption) -> some View {
        let icon = providerIcon(for: option)
        let name = option.displayName
        let size = option.sizeLabel

        switch downloadModel.state {
        case .downloaded:
            DownloadCompleteCard(
                modelIcon: icon,
                modelName: name,
                modelSize: size,
                modelDirectoryURL: downloadModel.modelDirectoryURL
            )
        case let .downloading(progress):
            DownloadProgressCard(
                modelIcon: icon,
                modelName: name,
                modelSize: size,
                progress: progress.fraction,
                speedText: progress.speedText,
                isPaused: false,
                onPause: { downloadModel.pauseDownload() },
                onResume: {},
                onCancel: { downloadModel.cancelDownload() }
            )
        case let .paused(progress):
            DownloadProgressCard(
                modelIcon: icon,
                modelName: name,
                modelSize: size,
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

    private var selectedModelRequiresDownload: Bool {
        downloadModel.selectedModelOption?.requiresDownload ?? true
    }

    private func providerIcon(for option: ModelOption) -> Image {
        switch option.provider {
        case .appleSpeech: .swiftLogo
        case .mlxAudioSTT: .qwen
        case .whisperKit: .openai
        case .voxtralCore: .mistral
        }
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
