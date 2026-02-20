import AppKit
import SwiftUI

public struct OnboardingView: View {
    @State private var currentPage: OnboardingModel.Page = .welcome
    @Bindable var model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            backgroundLayer

            Group {
                switch currentPage {
                case .welcome:
                    WelcomePage {
                        currentPage = .model
                    }

                case .model:
                    ModelSelectionPage(
                        model: model,
                        onContinue: { currentPage = .shortcut },
                        onBack: { currentPage = .welcome }
                    )

                case .shortcut:
                    ShortcutPage(
                        model: model,
                        onContinue: { currentPage = .microphone },
                        onBack: { currentPage = .model }
                    )

                case .microphone:
                    MicrophonePermissionPage(
                        model: model,
                        onContinue: { currentPage = .accessibility },
                        onBack: { currentPage = .shortcut }
                    )

                case .accessibility:
                    AccessibilityPermissionPage(
                        model: model,
                        onContinue: { currentPage = .historyRetention },
                        onBack: { currentPage = .microphone }
                    )

                case .historyRetention:
                    HistoryRetentionPage(
                        model: model,
                        onContinue: { currentPage = .download },
                        onBack: { currentPage = .accessibility }
                    )

                case .download:
                    DownloadPage(
                        model: model,
                        onCompletion: { model.completeSetup() },
                        onBack: { currentPage = .historyRetention }
                    )
                }
            }
            .transition(.scale)
            .animation(.easeIn, value: currentPage)
        }
        .frame(width: 820, height: 512)
        .preferredColorScheme(.dark)
        .onAppear {
            model.windowAppeared()
            DispatchQueue.main.async {
                ensureOnboardingWindowsAreVisible()
            }
        }
    }

    private var backgroundLayer: some View {
        Group {
            if NSImage(named: "blackhole") != nil {
                Image("blackhole")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.12)
                    .saturation(0.72)
                    .blur(radius: 64)
                    .opacity(0.75)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.10, blue: 0.22),
                        Color(red: 0.05, green: 0.04, blue: 0.14),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay {
            LinearGradient(
                colors: [
                    .black.opacity(0.25),
                    .black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func ensureOnboardingWindowsAreVisible() {
        let onboardingTitles = Set(["Gloam Onboarding", "gloam Settings"])

        for window in NSApp.windows where onboardingTitles.contains(window.title) {
            guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
                window.center()
                continue
            }

            var origin = window.frame.origin
            let maxX = screenFrame.maxX - window.frame.width
            let maxY = screenFrame.maxY - window.frame.height

            if origin.x < screenFrame.minX || origin.x > maxX || origin.y < screenFrame.minY || origin.y > maxY {
                origin = NSPoint(
                    x: screenFrame.midX - (window.frame.width / 2),
                    y: screenFrame.midY - (window.frame.height / 2)
                )
                window.setFrameOrigin(origin)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Welcome") {
    OnboardingView(model: .makePreview())
}

#Preview("Model Selection") {
    OnboardingView(model: .makePreview())
}
#endif
