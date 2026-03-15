import SwiftUI

struct RefiningCapsuleContent: View {
    var contentBlur: CGFloat = 0
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.intelligence")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Refining")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .floatingCapsuleChrome(blur: contentBlur)
        .overlay {
            ZStack {
                Capsule()
                    .fill(.clear)
                    .runningBorder(radius: 128, lineWidth: 4, animated: true, duration: 1)
                    .blur(radius: 12)

                Capsule()
                    .fill(.clear)
                    .runningBorder(radius: 128, lineWidth: 2, animated: true, duration: 1)
            }
        }
        .clipShape(.capsule)
    }
}

#if DEBUG
#Preview("Refining") {
    RefiningCapsuleContent()
        .padding(24)
        .frame(width: 280, height: 110)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
}
#endif
