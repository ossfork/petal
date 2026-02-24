import Assets
import Shared
import SwiftUI

struct ModelInfoRow: View {
    let option: ModelOption

    var body: some View {
        HStack(spacing: 14) {
            providerIcon
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(option.displayName)
                    .font(.headline)

                Text(option.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    ratingView(
                        icon: "bolt.fill",
                        score: option.descriptor.speedScore,
                        color: .orange
                    )
                    ratingView(
                        icon: "brain",
                        score: option.descriptor.smartScore,
                        color: .cyan
                    )

                    Text(option.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func ratingView(icon: String, score: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: icon)
                    .foregroundStyle(i < score ? AnyShapeStyle(color) : AnyShapeStyle(.quaternary))
            }
        }
        .font(.system(size: 9))
    }

    private var providerIcon: Image {
        switch option.provider {
        case .appleSpeech: .swiftLogo
        case .mlxAudioSTT: .qwen
        case .whisperKit: .openai
        case .voxtralCore: .mistral
        }
    }
}
