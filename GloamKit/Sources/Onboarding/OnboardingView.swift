import AppKit
import SwiftUI

public struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    public init(model: OnboardingModel) {
        self.model = model
    }

    public var body: some View {
        OnboardingPageContainer(
            showBack: model.showBack,
            backAction: model.moveBack,
            primaryTitle: model.currentPrimaryTitle,
            primaryDisabled: model.primaryDisabled,
            primaryActionDelay: model.currentPage.primaryActionDelay,
            primaryAction: model.primaryActionTapped
        ) { _ in
            Group {
                switch model.currentPage {
                case .welcome:
                    WelcomePage()

                case .model:
                    ModelSelectionPage(model: model)

                case .shortcut:
                    ShortcutPage(model: model)

                case .microphone:
                    MicrophonePermissionPage(model: model)

                case .accessibility:
                    AccessibilityPermissionPage(model: model)

                case .historyRetention:
                    HistoryRetentionPage(model: model)

                case .download:
                    DownloadPage(model: model)
                }
            }
            .transition(.scale)
            .animation(.easeIn, value: model.currentPage)
        }
        .frame(width: 820, height: 512)
        .background(backgroundLayer)
        .preferredColorScheme(.dark)
        .onChange(of: model.selectedModelID) { _, _ in
            model.selectedModelChanged()
        }
        .onChange(of: model.microphoneAuthorized) { _, authorized in
            if authorized, model.currentPage == .microphone {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    model.moveForward()
                }
            }
        }
        .onChange(of: model.accessibilityAuthorized) { _, authorized in
            if authorized, model.currentPage == .accessibility {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    model.moveForward()
                }
            }
        }
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

#Preview("Welcome") {
    OnboardingView(model: .makePreview(page: .welcome))
}

#Preview("Model Selection") {
    OnboardingView(model: .makePreview(page: .model))
}

#Preview("Shortcut") {
    OnboardingView(model: .makePreview(page: .shortcut))
}

#Preview("Microphone") {
    OnboardingView(model: .makePreview(page: .microphone))
}

#Preview("Accessibility") {
    OnboardingView(model: .makePreview(page: .accessibility))
}

#Preview("History Retention") {
    OnboardingView(model: .makePreview(page: .historyRetention))
}

#Preview("Download") {
    OnboardingView(model: .makePreview(page: .download))
}
