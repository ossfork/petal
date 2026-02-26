import Assets
import Shared
import SwiftUI
import UI

struct AppleIntelligencePage: View {
    @Bindable var model: OnboardingModel

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            iconStack
            titleGroup
                .slideIn(active: isAnimating, delay: 0.5)
            toggleRow
                .slideIn(active: isAnimating, delay: 0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .fill(.clear)
                .runningBorder(radius: 12, lineWidth: model.appleIntelligenceEnabled ? 64 : 2)
                .blur(radius: 96)
                .animation(.easeInOut, value: model.appleIntelligenceEnabled)
        }
        .onAppear { isAnimating = true }
    }

    private var iconStack: some View {
        ZStack {
            Image.appleIntelligence
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .offset(x: 48)
                .slideIn(active: isAnimating, blur: 1, scale: 0.25, delay: 0.5, animation: .easeInOut)

            Image.appIcon
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(radius: 8)
                .slideIn(active: isAnimating, blur: 1, scale: 0.5, delay: 0.25, animation: .easeInOut)
        }
        .offset(x: -24)
        .frame(height: 120)
    }

    private var titleGroup: some View {
        VStack(spacing: 8) {
            Text("Apple Intelligence")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("Enhance any model with on-device Apple Intelligence to fix grammar, punctuation, and formatting.\n\n**Additional procesing time will be added*")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
    }

    private var toggleRow: some View {
        Toggle("Enable Foundation Models", isOn: Binding(model.$appleIntelligenceEnabled))
            .toggleStyle(.switch)
            .font(.headline)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
    }
}

#if DEBUG

#Preview("Apple Intelligence - Off") {
    OnboardingView(model: .makePreview(page: .appleIntelligence) { model in
        model.$appleIntelligenceEnabled.withLock { $0 = false }
    })
}

#Preview("Apple Intelligence - On") {
    OnboardingView(model: .makePreview(page: .appleIntelligence) { model in
        model.$appleIntelligenceEnabled.withLock { $0 = true }
    })
}

#endif
