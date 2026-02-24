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

                Label(
                    option.sizeLabel
                        + " · "
                        + option.descriptor.parameters
                        + " · "
                        + option.providerDisplayName,
                    systemImage: "internaldrive"
                )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var providerIcon: Image {
        switch option.provider {
        case .mlxAudioSTT: .qwen
        case .whisperKit: .openai
        case .voxtralCore: .mistral
        }
    }
}
