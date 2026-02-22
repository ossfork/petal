import Shared
import SwiftUI
import UI

struct ModelOptionCard: View {
    let option: ModelOption
    let isSelected: Bool
    let onSelect: () -> Void

    // MARK: - Computed

    private var checkmarkIcon: String {
        isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var fillColor: Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.26)
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.08)
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.5 : 1
    }

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
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

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(option.displayName)
                    .font(.headline)

                if option.isRecommended {
                    recommendedBadge
                }
            }

            Text(option.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(option.sizeLabel)
                .font(.caption2)
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
    ModelOptionCard(option: .mini3b, isSelected: true) {}
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Unselected") {
    ModelOptionCard(option: .mini3b, isSelected: false) {}
        .padding()
        .preferredColorScheme(.dark)
}
