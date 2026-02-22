import SwiftUI
import UI

struct AccessibilityPermissionPage: View {
    @Bindable var model: OnboardingModel
    @State private var isAnimating = false

    var body: some View {
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
        }
        .onAppear { isAnimating = true }
    }

    private var iconStack: some View {
        ZStack {
            Image.accessibility
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .offset(x: 48)

            Image.appIcon
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
}

#Preview("Accessibility - Pending") {
    OnboardingView(model: .makePreview(page: .accessibility) { model in
        model.accessibilityAuthorized = false
    })
}

#Preview("Accessibility - Enabled") {
    OnboardingView(model: .makePreview(page: .accessibility))
}
