import SwiftUI

private struct FloatingCapsuleChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule().fill(backgroundColor)
            }
    }
}

extension View {
    func floatingCapsuleChrome() -> some View {
        modifier(FloatingCapsuleChrome())
    }
}
