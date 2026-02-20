import Shared
import SwiftUI

struct HistorySettingsSection: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                Picker("Retention", selection: historyRetentionMode) {
                    ForEach(HistoryRetentionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("History Path")
                        .font(.headline)
                    Text(viewModel.appModel.historyDirectoryDisplayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button("Open Folder") {
                        viewModel.openHistoryFolder()
                    }
                }
            }

            SettingsCard {
                Text("Recent Transcripts")
                    .font(.headline)

                let entries = viewModel.recentEntries

                if entries.isEmpty {
                    Text("No transcripts yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 10) {
                                Text(viewModel.appModel.historyTimestampText(for: entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button("Copy") {
                                    viewModel.copyHistoryEntry(entry)
                                }
                                .buttonStyle(.link)

                                if entry.audioRelativePath != nil {
                                    Button("Play") {
                                        viewModel.playHistoryAudio(entry)
                                    }
                                    .buttonStyle(.link)
                                }
                            }

                            Text(viewModel.appModel.historyMetadataText(for: entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(entry.transcript.isEmpty ? "Transcript not retained." : entry.transcript)
                                .font(.body)
                                .lineLimit(2)
                        }

                        if entry.id != entries.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bindings

    private var historyRetentionMode: Binding<HistoryRetentionMode> {
        Binding(
            get: { viewModel.appModel.historyRetentionMode },
            set: { viewModel.appModel.historyRetentionMode = $0 }
        )
    }
}
