import AppKit
import SwiftUI
import UI

struct WelcomePage: View {
    let onComplete: () -> Void

    init(_ onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        OnboardingPageContainer(
            primaryTitle: "Get Started",
            primaryActionDelay: 1.5,
            primaryAction: onComplete
        ) { isAnimating in
            VStack(spacing: 24) {
                onboardingAppIcon()
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .shadow(radius: 12)
                    .font(.system(size: 74))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .slideIn(active: isAnimating, delay: 0.25)

                VStack(spacing: 10) {
                    Text("Welcome to Gloam")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("On-device transcription, powered by local models.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .slideIn(active: isAnimating, delay: 0.5)
            }
        }
    }

    private func featureRow(symbol: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Welcome Page") {
    OnboardingPagePreview {
        WelcomePage {}
    }
}
