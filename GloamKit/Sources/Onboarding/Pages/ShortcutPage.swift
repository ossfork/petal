import KeyboardShortcuts
import SwiftUI
import UI

struct ShortcutPage: View {
    @Bindable var model: OnboardingModel
    let onComplete: () -> Void
    let onBack: () -> Void

    init(model: OnboardingModel, _ onComplete: @escaping () -> Void, _ onBack: @escaping () -> Void = {}) {
        self.model = model
        self.onComplete = onComplete
        self.onBack = onBack
    }

    var body: some View {
        OnboardingPageContainer(
            showBack: true,
            backAction: onBack,
            primaryTitle: "Continue",
            primaryDisabled: !model.hasConfiguredShortcut,
            primaryAction: {
                guard model.hasConfiguredShortcut else { return }
                onComplete()
            }
        ) { isAnimating in
            VStack(spacing: 28) {
                Image(systemName: "keyboard")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                    .slideIn(active: isAnimating, delay: 0.25)

                VStack(spacing: 8) {
                    Text("Set Your Shortcut")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Text("Use a key combo you can hit quickly in any app.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .slideIn(active: isAnimating, delay: 0.5)

                KeyboardShortcuts.Recorder("Push to talk", name: .pushToTalk)
                    .slideIn(active: isAnimating, delay: 1.0)

                Text("Tap and release quickly to toggle recording. Hold for at least 2 seconds for push-to-talk.")
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }
                    .slideIn(active: isAnimating, delay: 1.5)
            }
        }
    }
}

#Preview("Shortcut Page") {
    OnboardingPagePreview {
        ShortcutPage(model: .makePreview()) {}
    }
}
