import SwiftUI

public extension View {
    func capsulePill<S: ShapeStyle>(
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        fill: S
    ) -> some View {
        padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(fill, in: Capsule())
    }

    func slideIn(
        active: Bool,
        offset: CGFloat = 20,
        opacity: CGFloat = 0,
        blur: CGFloat = 0,
        scale: CGFloat = 1,
        delay: CGFloat = 0,
        duration: CGFloat = 1.0,
        animation: Animation = .easeIn
    ) -> some View {
        self
            .opacity(active ? 1 : opacity)
            .blur(radius: active ? 0 : blur)
            .offset(y: active ? 0 : offset)
            .scaleEffect(active ? 1 : scale)
            .animation(animation.speed(duration).delay(delay), value: active)
    }
}
