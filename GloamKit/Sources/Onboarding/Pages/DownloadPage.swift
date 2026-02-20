import Shared
import SwiftUI

struct DownloadPage: View {
    @Bindable var model: OnboardingModel
    let onCompletion: () -> Void
    let onBack: () -> Void

    @State private var animating = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                        .slideIn(active: animating, delay: 0.25)

                    VStack(spacing: 8) {
                        Text("Download Model")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        Text("Download your selected model to get started.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .slideIn(active: animating, delay: 0.5)

                    modelSummaryCard
                        .slideIn(active: animating, delay: 0.75)

                    if model.isDownloadingModel || model.downloadProgress > 0 || !model.downloadStatus.isEmpty {
                        downloadProgressCard
                            .slideIn(active: animating, delay: 1.0)
                    }

                    if let error = model.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 34)
            }
            .scrollIndicators(.hidden)

            OnboardingActionBar(
                showBack: !model.isDownloadingModel,
                backAction: onBack,
                primaryTitle: primaryButtonTitle,
                primaryDisabled: model.isDownloadingModel,
                primaryAction: primaryAction
            )
        }
        .onAppear { animating = true }
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
                Text(model.downloadStatus.isEmpty ? "Download status" : model.downloadStatus)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(model.downloadSummaryText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: model.downloadProgress)

            if let speedText = model.downloadSpeedText {
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

    private var primaryButtonTitle: String {
        if model.isDownloadingModel {
            return "Downloading..."
        }
        if model.isSelectedModelDownloaded {
            return "Finish Setup"
        }
        return "Download Model"
    }

    private func primaryAction() {
        if model.isSelectedModelDownloaded {
            model.completeSetup()
            onCompletion()
            return
        }

        Task { await model.downloadModel() }
    }
}
