import Assets
import SwiftUI
import UI

struct MicrophonePermissionPage: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        PermissionPage(
            title: "Enable Microphone",
            subtitle: "Gloam needs microphone access to record and transcribe your voice.",
            icon: .microphone,
            isAuthorized: model.microphoneAuthorized
        )
    }
}

#Preview("Microphone - Pending") {
    OnboardingView(model: .makePreview(page: .microphone) { model in
        model.microphonePermissionState = .notDetermined
        model.microphoneAuthorized = false
    })
}

#Preview("Microphone - Enabled") {
    OnboardingView(model: .makePreview(page: .microphone))
}
