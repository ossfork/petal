import AppKit
import SwiftUI

struct DownloadCompleteCard: View {
    let modelDirectoryURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                Text("Model ready")
                    .font(.headline)

                Spacer()
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
        modelDirectoryURL: URL(fileURLWithPath: "/tmp")
    )
    .padding()
    .frame(width: 400)
}
