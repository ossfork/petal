import SwiftUI

public extension View {
    func xSpacing(_ alignment: Alignment) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
