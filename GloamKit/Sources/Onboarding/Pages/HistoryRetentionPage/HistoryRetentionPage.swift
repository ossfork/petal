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
                title: "Choose What to Keep",
                description: "Decide what Gloam stores after each transcription.",
                layout: .vertical
            )
            .slideIn(active: isAnimating, delay: 0.25)

            HStack(alignment: .top, spacing: 12) {
                RetentionCard(
                    symbol: "doc.text",
                    title: "Text Only",
                    description: "Save the transcription text. Audio is not stored.",
                    isSelected: model.historyRetentionMode == .transcripts
                ) { model.historyRetentionMode = .transcripts }

                RetentionCard(
                    symbol: "doc.text.below.ecg",
                    title: "Everything",
                    description: "Keep audio recordings and transcription text.",
                    recommended: true,
                    isSelected: model.historyRetentionMode == .both
                ) { model.historyRetentionMode = .both }

                RetentionCard(
                    symbol: "hand.raised.fill",
                    title: "Private",
                    description: "Nothing is saved. Transcriptions are pasted and discarded.",
                    isSelected: model.historyRetentionMode == .none
                ) { model.historyRetentionMode = .none }
            }
            .frame(height: 220)
            .slideIn(active: isAnimating, delay: 0.5)

            Spacer()
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

#Preview("History Retention - Transcripts") {
    OnboardingView(model: .makePreview(page: .historyRetention) { model in
        model.historyRetentionMode = .transcripts
    })
}
