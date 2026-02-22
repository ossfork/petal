import SwiftUI
import UI

struct AccessibilityPermissionPage: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        PermissionPage(
            title: "Enable Accessibility",
            subtitle: "Gloam needs accessibility to paste transcriptions directly.",
            icon: Image.accessibility,
            isAuthorized: model.accessibilityAuthorized
        )
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
