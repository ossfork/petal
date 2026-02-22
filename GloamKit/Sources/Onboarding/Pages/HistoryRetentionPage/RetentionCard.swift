import Shared
import SwiftUI
import UI

struct RetentionCard: View {
    let symbol: String
    let title: String
    let description: String
    let recommended: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    init(
        symbol: String,
        title: String,
        description: String,
        recommended: Bool = false,
        isSelected: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.title = title
        self.description = description
        self.recommended = recommended
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    // MARK: - Computed

    private var borderColor: Color {
        isSelected ? Color.white.opacity(0.6) : Color.white.opacity(0.15)
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }

    private var checkmarkIcon: String {
        isSelected ? "checkmark.circle.fill" : "circle"
    }

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 40, height: 40)
                    .padding(.bottom, 8)

                Text(title)
                    .font(.title3.weight(.semibold))

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: checkmarkIcon)
                    .font(.body)
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.2))
                    .padding(14)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .overlay(alignment: .topTrailing) {
                if recommended {
                    recommendedBadge
                        .padding(.trailing, 8)
                        .offset(y: -10)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Subviews

    private var recommendedBadge: some View {
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

// MARK: - Previews

#Preview("Selected") {
    RetentionCard(
        symbol: "doc.text.below.ecg",
        title: "Audio + Transcripts",
        description: "Save both audio recordings and transcription text for full history.",
        recommended: true,
        isSelected: true
    ) {}
        .frame(width: 220, height: 220)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Unselected") {
    RetentionCard(
        symbol: "hand.raised.fill",
        title: "Private",
        description: "Nothing is saved to disk. Transcriptions are pasted to your clipboard and forgotten.",
        isSelected: false
    ) {}
        .frame(width: 220, height: 220)
        .padding()
        .preferredColorScheme(.dark)
}
