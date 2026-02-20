import AppKit
import SwiftUI

struct MicrophonePermissionPage: View {
    @Bindable var model: OnboardingModel
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var animating = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    iconStack
                        .slideIn(active: animating, delay: 0.25)

                    VStack(spacing: 8) {
                        Text("Enable Microphone")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        Text("Gloam needs microphone access to record and transcribe your voice.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .slideIn(active: animating, delay: 0.5)

                    statusIndicator
                        .slideIn(active: animating, delay: 1.0)

                    actionButton
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
                primaryDisabled: !model.microphoneAuthorized,
                primaryAction: onContinue
            )
        }
        .onAppear { animating = true }
        .onChange(of: model.microphoneAuthorized) { _, authorized in
            if authorized {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    onContinue()
                }
            }
        }
    }

    private var iconStack: some View {
        ZStack {
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
                .offset(x: 48)

            if let appIcon = onboardingAppIcon() {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(radius: 8)
            } else {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 58))
            }
        }
        .frame(height: 120)
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.microphoneAuthorized ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(model.microphoneAuthorized ? "Enabled" : "Permission Pending")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder
    private var actionButton: some View {
        if model.microphoneAuthorized {
            ComposeSecondaryButton("Continue", systemImage: "checkmark.circle.fill") {
                onContinue()
            }
        } else {
            ComposeSecondaryButton(model.microphonePermissionActionTitle, systemImage: "mic.fill") {
                Task { await model.microphonePermissionButtonTapped() }
            }
        }
    }
}
