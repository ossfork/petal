import SwiftUI

struct RecordingBars: View {
    let level: Double

    private let pattern: [CGFloat] = [0.22, 0.44, 0.76, 1.0, 0.76, 0.44, 0.22]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(self.pattern.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.red.opacity(0.85))
                    .frame(width: 2.8, height: self.barHeight(base: value))
            }
        }
        .frame(height: 16)
        .animation(.linear(duration: 0.1), value: self.level)
    }

    private func barHeight(base: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, level))
        let boosted = pow(clamped, 0.5) // sqrt curve — much more sensitive to quiet input
        let scale = boosted * 14
        return 2 + (scale * base)
    }
}

#if DEBUG
#Preview("Recording Bars") {
    RecordingBars(level: 0.6)
        .padding()
}
#endif
