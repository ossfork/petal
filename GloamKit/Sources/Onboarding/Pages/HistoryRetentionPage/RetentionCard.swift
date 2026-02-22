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

    private var fillColor: Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.26)
    }

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
            HStack(alignment: .top, spacing: 12) {
                icon
                details
                Spacer(minLength: 8)
                checkmark
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(fillColor))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subviews

    private var icon: some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(width: 28)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)

                if recommended {
                    recommendedBadge
                }
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recommendedBadge: some View {
        Text("Recommended")
            .font(.caption2.weight(.semibold))
            .capsulePill(
                horizontalPadding: 8,
                verticalPadding: 4,
                fill: Color.green.opacity(0.22)
            )
            .foregroundStyle(.green)
    }

    private var checkmark: some View {
        Image(systemName: checkmarkIcon)
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
    }
}

// MARK: - Previews

#Preview("Selected") {
    RetentionCard(
        symbol: "doc.text.below.ecg",
        title: "Audio + Transcripts",
        description: "Save both audio and text.",
        recommended: true,
        isSelected: true
    ) {}
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Unselected") {
    RetentionCard(
        symbol: "xmark.circle",
        title: "Nothing",
        description: "Nothing saved. Transcriptions are pasted and forgotten.",
        isSelected: false
    ) {}
        .padding()
        .preferredColorScheme(.dark)
}
