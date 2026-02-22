import SwiftUI

public struct RecommendedBadge: View {
    public init() {}

    public var body: some View {
        Text("Recommended")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.orange.opacity(0.7).gradient)
            )
    }
}
