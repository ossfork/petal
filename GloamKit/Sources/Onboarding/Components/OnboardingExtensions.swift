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
            content(isAnimating)
                .padding()
                .xSpacing(.topLeading)

            VStack(spacing: 0) {
                Divider()

                HStack(spacing: 10) {
                    if showBack, let backAction {
                        LongButton("Back", symbol: "chevron.left", variant: .secondary) {
                            backAction()
                        }
                        .frame(width: 220)
                    }
                    Spacer()

                    LongButton(primaryTitle, variant: .primary, luminous: true) {
                        primaryAction()
                    }
                    .disabled(primaryDisabled)
                    .frame(width: 220)
                }
                .padding([.horizontal, .bottom])
                .background(.regularMaterial)
            }
            .slideIn(active: isAnimating, delay: primaryActionDelay)
        }
        .onAppear { isAnimating = true }
    }
}

#Preview("Welcome") {
    OnboardingView(model: .makePreview(page: .welcome))
}
