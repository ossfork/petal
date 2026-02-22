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
                title: "Choose your model",
                description: "Select the local model that fits your speed and quality balance.",
                layout: .vertical
            )
            .slideIn(active: isAnimating, delay: 0.25)

            VStack(spacing: 10) {
                ForEach(ModelOption.allCases) { option in
                    modelOptionCard(option)
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
        }
        .onAppear { isAnimating = true }
    }

    private func modelOptionCard(_ option: ModelOption) -> some View {
        let isSelected = option.rawValue == model.selectedModelID

        return Button {
            model.selectedModelID = option.rawValue
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(option.displayName)
                            .font(.headline)

                        if option.isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .capsulePill(
                                    horizontalPadding: 8,
                                    verticalPadding: 4,
                                    fill: Color.green.opacity(0.22)
                                )
                                .foregroundStyle(.green)
                        }
                    }

                    Text(option.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(option.sizeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.26))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Model Selection - Recommended") {
    OnboardingPagePreview {
        ModelSelectionPage(model: .makePreview())
            .padding()
    }
}
