import SwiftUI
import UI

struct WelcomePage: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            Image.appIcon
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .shadow(radius: 12)
                .font(.system(size: 74))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .slideIn(active: isAnimating, delay: 0.25)

            VStack(spacing: 10) {
                Text("Welcome to Gloam")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("On-device transcription, powered by local models.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .slideIn(active: isAnimating, delay: 0.5)
        }
        .onAppear { isAnimating = true }
    }
}

#Preview("Welcome") {
    OnboardingView(model: .makePreview(page: .welcome))
}
