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
}
