import Shared
import SwiftUI
import UI

struct ModelSelectionPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                symbol: "externaldrive.fill",
                title: "Choose a Model",
                description: "Transcription runs entirely on-device. Select a model to get started.",
                layout: .vertical
            )
            .slideIn(active: isAnimating, delay: 0.25)

            VStack(spacing: 10) {
                ForEach(ModelOption.allCases) { option in
                    ModelOptionCard(
                        option: option,
                        isSelected: option.rawValue == model.selectedModelID
                    ) {
                        model.selectedModelID = option.rawValue
                    }
                }
            }
            .slideIn(active: isAnimating, delay: 0.5)

            if let option = model.selectedModelOption {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Label(option.sizeLabel, systemImage: "externaldrive")
                        Label(option.rawValue, systemImage: "cpu")
                    }
                    .font(.caption)

                    Text(option.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .slideIn(active: isAnimating, delay: 0.75)
            }

            Spacer()
        }
        .onAppear { isAnimating = true }
    }
}

#Preview("Model Selection") {
    OnboardingView(model: .makePreview(page: .model))
}
