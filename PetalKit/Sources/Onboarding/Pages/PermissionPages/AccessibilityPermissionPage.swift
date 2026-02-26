import SwiftUI
import UI

struct AccessibilityPermissionPage: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        PermissionPage(
            title: "Accessibility Access",
            subtitle: "To paste transcriptions into your active app, Petal needs accessibility access.",
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
