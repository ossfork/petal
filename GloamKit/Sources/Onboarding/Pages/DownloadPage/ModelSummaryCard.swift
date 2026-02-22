import Shared
import SwiftUI

struct ModelSummaryCard: View {
    let option: ModelOption

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(option.displayName, systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(option.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Label(option.descriptor.quantization, systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(option.descriptor.parameters, systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Previews

#Preview("Summary Card") {
    ModelSummaryCard(option: .mini3b)
        .padding()
        .preferredColorScheme(.dark)
}
