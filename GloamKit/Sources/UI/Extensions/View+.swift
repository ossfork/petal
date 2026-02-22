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

    func hSpacing(_ alignment: Alignment) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
    }

    func vSpacing(_ alignment: Alignment) -> some View {
        frame(maxHeight: .infinity, alignment: alignment)
    }

    func xSpacing(_ alignment: Alignment) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
