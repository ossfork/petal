import SwiftUI

private struct FloatingCapsuleChrome: ViewModifier {
    var blur: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .frame(height: 16)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule().fill(backgroundColor).blur(radius: blur > 0 ? 6 : 0)
            }
    }
}

extension View {
    func floatingCapsuleChrome(blur: CGFloat = 0) -> some View {
        modifier(FloatingCapsuleChrome(blur: blur))
    }
}
