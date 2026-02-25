import AppKit
import Assets
import SwiftUI

struct DownloadCompleteCard: View {
    let modelIcon: Image
    let modelName: String
    let modelSize: String?
    let modelDirectoryURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                modelIcon
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(modelName)
                    .font(.headline)

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }

            if modelDirectoryURL != nil {
                Button(action: showInFinder) {
                    Label("Show in Finder", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    private func showInFinder() {
        guard let url = modelDirectoryURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

#Preview {
    DownloadCompleteCard(
        modelIcon: .qwen,
        modelName: "Qwen3 ASR 0.6B (4-bit)",
        modelSize: "~1.2 GB",
        modelDirectoryURL: URL(fileURLWithPath: "/tmp")
    )
    .padding()
    .frame(width: 400)
}
