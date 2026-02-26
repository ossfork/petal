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
                description: "This shortcut works two ways — hold it down and release to finish, or quick-tap to start and tap again to stop.",
                layout: .vertical
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .slideIn(active: isAnimating, delay: 0.25)

            Spacer()

            KeyboardShortcuts.Recorder(for: .pushToTalk)
                .scaleEffect(2.0)
                .slideIn(active: isAnimating, delay: 0.5)

            Spacer()
        }
        .onAppear { isAnimating = true }
    }
}

#Preview("Shortcut") {
    OnboardingView(model: .makePreview(page: .shortcut))
}
