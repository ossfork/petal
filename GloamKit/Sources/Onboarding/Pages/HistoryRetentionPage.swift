import Shared
import SwiftUI
import UI

struct HistoryRetentionPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .slideIn(active: isAnimating, delay: 0.25)

            VStack(spacing: 8) {
                Text("History & Retention")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("Choose what Gloam saves after each transcription.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .slideIn(active: isAnimating, delay: 0.5)

            VStack(spacing: 10) {
                retentionCard(
                    mode: .none,
                    symbol: "xmark.circle",
                    title: "Nothing",
                    description: "Nothing saved. Transcriptions are pasted and forgotten."
                )
                .slideIn(active: isAnimating, delay: 0.75)

                retentionCard(
                    mode: .transcripts,
                    symbol: "doc.text",
                    title: "Transcripts Only",
                    description: "Save transcription text only."
                )
                .slideIn(active: isAnimating, delay: 1.0)

                retentionCard(
                    mode: .audio,
                    symbol: "waveform",
                    title: "Audio Only",
                    description: "Save audio recordings only."
                )
                .slideIn(active: isAnimating, delay: 1.25)

                retentionCard(
                    mode: .both,
                    symbol: "doc.text.below.ecg",
                    title: "Audio + Transcripts",
                    description: "Save both audio and text.",
                    recommended: true
                )
                .slideIn(active: isAnimating, delay: 1.5)
            }
        }
        .onAppear { isAnimating = true }
    }

    private func retentionCard(
        mode: HistoryRetentionMode,
        symbol: String,
        title: String,
        description: String,
        recommended: Bool = false
    ) -> some View {
        let isSelected = model.historyRetentionMode == mode

        return Button {
            model.historyRetentionMode = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)

                        if recommended {
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

                    Text(description)
                        .font(.caption)
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

#Preview("History Retention") {
    OnboardingView(model: .makePreview(page: .historyRetention))
}

#Preview("History Retention - Off") {
    OnboardingView(model: .makePreview(page: .historyRetention) { model in
        model.historyRetentionMode = .none
    })
}
