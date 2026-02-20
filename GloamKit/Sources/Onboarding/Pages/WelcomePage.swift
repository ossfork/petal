import AppKit
import SwiftUI

struct WelcomePage: View {
    let onContinue: () -> Void

    @State private var animating = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    appIconView
                        .slideIn(active: animating, delay: 0.25)

                    VStack(spacing: 10) {
                        Text("Welcome to Gloam")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)

                        Text("On-device transcription, powered by local models.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .slideIn(active: animating, delay: 0.5)

                    VStack(alignment: .leading, spacing: 14) {
                        featureRow(
                            symbol: "sparkles",
                            title: "Fast everywhere",
                            description: "Start recording instantly from your global shortcut."
                        )
                        .slideIn(active: animating, delay: 0.75)

                        featureRow(
                            symbol: "slider.horizontal.3",
                            title: "Choose your model",
                            description: "Pick the model size that fits your speed and quality needs."
                        )
                        .slideIn(active: animating, delay: 1.0)

                        featureRow(
                            symbol: "lock.shield",
                            title: "Private by default",
                            description: "Transcription runs locally on your Mac using downloaded models."
                        )
                        .slideIn(active: animating, delay: 1.25)
                    }
                    .frame(maxWidth: 420)

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 34)
            }
            .scrollIndicators(.hidden)

            OnboardingActionBar(
                primaryTitle: "Get Started",
                primaryAction: onContinue
            )
            .slideIn(active: animating, delay: 1.5)
        }
        .onAppear { animating = true }
    }

    @ViewBuilder
    private var appIconView: some View {
        if let appIcon = onboardingAppIcon() {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .shadow(radius: 12)
        } else {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 74))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
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
