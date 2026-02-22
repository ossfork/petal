import KeyboardShortcuts
import SwiftUI
import UI

struct ShortcutPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 28) {
            OnboardingHeader(
                symbol: "keyboard",
                title: "Record a Shortcut",
                description: "Set a global key combo to instantly start and stop transcription from anywhere.",
                layout: .vertical
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .slideIn(active: isAnimating, delay: 0.25)

            Spacer()

            KeyboardShortcuts.Recorder("", name: .pushToTalk)
                .controlSize(.large)
                .scaleEffect(3.0)
                .slideIn(active: isAnimating, delay: 0.5)

            Spacer()

            Text("⌥ Space is set as the default — click above to change it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .slideIn(active: isAnimating, delay: 0.75)
        }
        .onAppear { isAnimating = true }
    }
}

#Preview("Shortcut") {
    OnboardingView(model: .makePreview(page: .shortcut))
}
