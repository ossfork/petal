import AppKit
import SwiftUI
import UI

struct OnboardingPageContainer<Content: View>: View {
    let showBack: Bool
    let backAction: (() -> Void)?
    let primaryTitle: String
    let primaryDisabled: Bool
    let primaryAction: () -> Void
    let primaryActionDelay: CGFloat
    @ViewBuilder let content: (_ isAnimating: Bool) -> Content

    @State private var isAnimating = false

    init(
        showBack: Bool = false,
        backAction: (() -> Void)? = nil,
        primaryTitle: String,
        primaryDisabled: Bool = false,
        primaryActionDelay: CGFloat = 0.1,
        primaryAction: @escaping () -> Void,
        @ViewBuilder content: @escaping (_ isAnimating: Bool) -> Content
    ) {
        self.showBack = showBack
        self.backAction = backAction
        self.primaryTitle = primaryTitle
        self.primaryDisabled = primaryDisabled
        self.primaryActionDelay = primaryActionDelay
        self.primaryAction = primaryAction
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content(isAnimating)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .scrollIndicators(.hidden)

            OnboardingActionBar(
                showBack: showBack,
                backAction: backAction,
                primaryTitle: primaryTitle,
                primaryDisabled: primaryDisabled,
                primaryAction: primaryAction
            )
            .slideIn(active: isAnimating, delay: primaryActionDelay)
        }
        .onAppear { isAnimating = true }
    }
}

@MainActor
func onboardingAppIcon() -> Image {
    if let applicationIcon = NSApp.applicationIconImage,
       applicationIcon.size != .zero {
        return Image(nsImage: applicationIcon)
    }

    return Image(systemName: "waveform.badge.mic")
}

struct OnboardingPagePreview<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.10, blue: 0.22),
                    Color(red: 0.05, green: 0.04, blue: 0.14),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 512)
        .preferredColorScheme(.dark)
    }
}
