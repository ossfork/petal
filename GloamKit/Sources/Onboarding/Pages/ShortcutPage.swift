import KeyboardShortcuts
import SwiftUI

struct ShortcutPage: View {
    @Bindable var model: OnboardingModel
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var animating = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 24)

                    Image(systemName: "keyboard")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                        .slideIn(active: animating, delay: 0.25)

                    VStack(spacing: 8) {
                        Text("Set Your Shortcut")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        Text("Use a key combo you can hit quickly in any app.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .slideIn(active: animating, delay: 0.5)

                    KeyboardShortcuts.Recorder("Push to talk", name: .pushToTalk)
                        .slideIn(active: animating, delay: 1.0)

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
                        .slideIn(active: animating, delay: 1.5)

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 34)
            }
            .scrollIndicators(.hidden)

            OnboardingActionBar(
                showBack: true,
                backAction: onBack,
                primaryTitle: "Continue",
                primaryDisabled: !model.hasConfiguredShortcut,
                primaryAction: {
                    guard model.hasConfiguredShortcut else { return }
                    onContinue()
                }
            )
        }
        .onAppear { animating = true }
    }
}
