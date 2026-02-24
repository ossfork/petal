import SwiftUI

extension View {
    func floatingCapsuleChrome() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if #available(macOS 26.0, *) {
                    Capsule().fill(.ultraThinMaterial).glassEffect(in: .capsule)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
    }
}
