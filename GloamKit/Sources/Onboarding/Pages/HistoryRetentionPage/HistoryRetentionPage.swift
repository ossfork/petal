import Shared
import SwiftUI
import UI

struct HistoryRetentionPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                title: "History & Retention",
                description: "Choose what Gloam saves after each transcription.",
                layout: .vertical
            )
            .slideIn(active: isAnimating, delay: 0.25)

            VStack(spacing: 10) {
                RetentionCard(
                    symbol: "xmark.circle",
                    title: "Nothing",
                    description: "Nothing saved. Transcriptions are pasted and forgotten.",
                    isSelected: model.historyRetentionMode == .none
                ) { model.historyRetentionMode = .none }

                RetentionCard(
                    symbol: "doc.text",
                    title: "Transcripts Only",
                    description: "Save transcription text only.",
                    isSelected: model.historyRetentionMode == .transcripts
                ) { model.historyRetentionMode = .transcripts }

                RetentionCard(
                    symbol: "waveform",
                    title: "Audio Only",
                    description: "Save audio recordings only.",
                    isSelected: model.historyRetentionMode == .audio
                ) { model.historyRetentionMode = .audio }

                RetentionCard(
                    symbol: "doc.text.below.ecg",
                    title: "Audio + Transcripts",
                    description: "Save both audio and text.",
                    recommended: true,
                    isSelected: model.historyRetentionMode == .both
                ) { model.historyRetentionMode = .both }
            }
            .slideIn(active: isAnimating, delay: 0.5)
        }
        .onAppear { isAnimating = true }
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
