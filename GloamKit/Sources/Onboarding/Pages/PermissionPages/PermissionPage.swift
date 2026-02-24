import SwiftUI
import UI

struct PermissionPage: View {
    let title: String
    let subtitle: String
    let icon: Image
    let isAuthorized: Bool

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            iconStack
            titleGroup
                .slideIn(active: isAnimating, delay: 0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            statusIndicator
                .slideIn(active: isAnimating, delay: 1.0)
        }
        .onAppear { isAnimating = true }
    }

    private var iconStack: some View {
        ZStack {
            permissionIcon
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

    private var permissionIcon: some View {
        icon
            .resizable()
            .scaledToFit()
            .frame(width: 76, height: 76)
            .offset(x: 48)
    }

    private var titleGroup: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isAuthorized ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isAuthorized ? "Enabled" : "Not Enabled")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
