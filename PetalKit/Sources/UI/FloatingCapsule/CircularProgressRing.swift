import SwiftUI

public struct CircularProgressRing: View {
    let progress: Double
    var size: CGFloat
    var lineWidth: CGFloat

    public init(progress: Double, size: CGFloat = 16, lineWidth: CGFloat = 2.5) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.28), lineWidth: self.lineWidth)

            Circle()
                .trim(from: 0, to: max(0.02, min(1, self.progress)))
                .stroke(.primary, style: StrokeStyle(lineWidth: self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: self.size, height: self.size)
        .animation(.linear(duration: 0.15), value: self.progress)
    }
}

#if DEBUG
#Preview("Progress Ring") {
    CircularProgressRing(progress: 0.65)
        .padding()
}
#endif
