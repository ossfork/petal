import Onboarding
import Shared
import SwiftUI
import UI

struct ModelSettingsSection: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsCard {
            Picker("Selected Model", selection: selectedModelID) {
                ForEach(ModelOption.allCases, id: \.rawValue) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }

            Divider()

            if let option = viewModel.modelDownloadViewModel.selectedModelOption {
                Text(option.summary)
                    .foregroundStyle(.secondary)

                LabeledContent("Model Size") {
                    Text(option.sizeLabel)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Download Status") {
                Text(downloadStatusText)
                    .foregroundStyle(downloadStatusColor)
            }

            if shouldShowProgress {
                ProgressView(value: viewModel.modelDownloadViewModel.downloadProgress)

                HStack {
                    Text(viewModel.modelDownloadViewModel.downloadSummaryText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let speedText = viewModel.modelDownloadViewModel.downloadSpeedText {
                        Text(speedText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let downloadError = viewModel.modelDownloadViewModel.lastError {
                Text(downloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 10) {
                LongButton(downloadButtonTitle, symbol: "arrow.down.circle") {
                    viewModel.downloadModel()
                }
                .disabled(viewModel.modelDownloadViewModel.isDownloadingModel || viewModel.modelDownloadViewModel.isSelectedModelDownloaded)

                LongButton("Open Setup Assistant", symbol: "wand.and.stars") {
                    viewModel.openSetupAssistant()
                }
            }
        }
    }

    // MARK: - Helpers

    private var selectedModelID: Binding<String> {
        Binding(
            get: { viewModel.modelDownloadViewModel.selectedModelID },
            set: { viewModel.selectModel($0) }
        )
    }

    private var shouldShowProgress: Bool {
        let dm = viewModel.modelDownloadViewModel
        return dm.isDownloadingModel
            || dm.downloadProgress > 0
            || !dm.downloadStatus.isEmpty
    }

    private var downloadButtonTitle: String {
        let dm = viewModel.modelDownloadViewModel
        if dm.isDownloadingModel { return "Downloading..." }
        if dm.isSelectedModelDownloaded { return "Downloaded" }
        return "Download Model"
    }

    private var downloadStatusText: String {
        let dm = viewModel.modelDownloadViewModel
        if dm.isDownloadingModel {
            return dm.downloadStatus.isEmpty ? "Downloading..." : dm.downloadStatus
        }
        if dm.lastError != nil { return "Failed" }
        if dm.isSelectedModelDownloaded { return "Downloaded" }
        if !dm.downloadStatus.isEmpty { return dm.downloadStatus }
        return "Not Downloaded"
    }

    private var downloadStatusColor: Color {
        let dm = viewModel.modelDownloadViewModel
        if dm.isDownloadingModel { return .blue }
        if dm.lastError != nil { return .red }
        if dm.isSelectedModelDownloaded { return .green }
        return .orange
    }
}
