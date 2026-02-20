import AppKit
import SwiftUI
import UI

struct AccessibilityPermissionPage: View {
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
            primaryDisabled: !model.accessibilityAuthorized,
            primaryAction: onComplete
        ) { isAnimating in
            VStack(spacing: 24) {
                iconStack
                    .slideIn(active: isAnimating, delay: 0.25)

                VStack(spacing: 8) {
                    Text("Enable Accessibility")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Text("Gloam needs accessibility to paste transcriptions directly.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .slideIn(active: isAnimating, delay: 0.5)

                statusIndicator
                    .slideIn(active: isAnimating, delay: 1.0)

                actionButton
                    .slideIn(active: isAnimating, delay: 1.5)
            }
        }
        .onChange(of: model.accessibilityAuthorized) { _, authorized in
            if authorized {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    onComplete()
                }
            }
        }
    }

    private var iconStack: some View {
        ZStack {
            Image("accessibility")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .offset(x: 48)

            onboardingAppIcon()
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(radius: 8)
                .font(.system(size: 58))
        }
        .frame(height: 120)
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.accessibilityAuthorized ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(model.accessibilityAuthorized ? "Enabled" : "Permission Pending")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder
    private var actionButton: some View {
        if !model.accessibilityAuthorized {
            LongButton("Enable Accessibility", symbol: "figure.wave", variant: .secondary) {
                model.accessibilityPermissionButtonTapped()
            }
        }
    }

}

#Preview("Accessibility - Pending") {
    OnboardingPagePreview {
        AccessibilityPermissionPage(
            model: .makePreview { model in
                model.accessibilityAuthorized = false
            }
        ) {}
    }
}

#Preview("Accessibility - Enabled") {
    OnboardingPagePreview {
        AccessibilityPermissionPage(model: .makePreview()) {}
    }
}
