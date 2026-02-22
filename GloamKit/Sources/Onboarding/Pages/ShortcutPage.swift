import KeyboardShortcuts
import SwiftUI
import UI

struct ShortcutPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingHeader(
                symbol: "keyboard",
                title: "Set Your Shortcut",
                description: "Use a key combo you can hit quickly in any app.",
                layout: .vertical
            )
            .slideIn(active: isAnimating, delay: 0.25)

            KeyboardShortcuts.Recorder("Push to talk", name: .pushToTalk)
                .slideIn(active: isAnimating, delay: 0.5)

            Text("Tap and release quickly to toggle recording. Hold for at least 2 seconds for push-to-talk.")
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
                .slideIn(active: isAnimating, delay: 0.75)

            Spacer()
        }
        .onAppear { isAnimating = true }
    }
}

#Preview("Shortcut") {
    OnboardingView(model: .makePreview(page: .shortcut))
}
