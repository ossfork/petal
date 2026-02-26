import AppKit
import SwiftUI
import UI

struct OnboardingPageContainer<Content: View>: View {
    var showBack = false
    var backAction: (() -> Void)?
    var primaryTitle: String
    var primaryDisabled = false
    var primaryAction: () -> Void
    var primaryActionDelay: CGFloat = 0.1
    @ViewBuilder var content: Content

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .safeAreaPadding([.horizontal, .bottom])
            bottomBar
        }
        .onAppear { isAnimating = true }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if showBack, let backAction {
                    LongButton("Back", symbol: "chevron.left", variant: .secondary, action: backAction)
                        .frame(width: 220)
                }
                Spacer()
                LongButton(primaryTitle, variant: .primary, luminous: true, action: primaryAction)
                    .disabled(primaryDisabled)
                    .frame(width: 220)
            }
            .padding(12)
            .background(.regularMaterial)
        }
        .slideIn(active: isAnimating, delay: primaryActionDelay)
    }
}

#if DEBUG

#Preview("Welcome") {
    OnboardingView(model: .makePreview(page: .welcome))
}

#endif
