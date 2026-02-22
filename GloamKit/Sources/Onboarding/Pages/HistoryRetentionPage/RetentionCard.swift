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
        isSelected ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.08)
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.5 : 1
    }

    private var checkmarkIcon: String {
        isSelected ? "checkmark.circle.fill" : "circle"
    }

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 32, height: 32)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
            .overlay(alignment: .topTrailing) {
                Image(systemName: checkmarkIcon)
                    .font(.body)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.2))
                    .padding(12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .overlay(alignment: .topLeading) {
                if recommended {
                    recommendedBadge
                        .offset(x: -6, y: -10)
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
                Capsule().fill(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
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
        .frame(width: 220, height: 200)
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
        .frame(width: 220, height: 200)
        .padding()
        .preferredColorScheme(.dark)
}
