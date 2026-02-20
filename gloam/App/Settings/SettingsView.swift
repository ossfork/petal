import Shared
import SwiftUI
import PermissionsClient

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedSection) {
                ForEach(viewModel.sidebarGroups) { group in
                    if let title = group.title {
                        Section(title) {
                            sidebarRows(for: group.items)
                        }
                    } else {
                        sidebarRows(for: group.items)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    detailView(for: viewModel.selectedSection)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(viewModel.selectedSection.title)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private func sidebarRows(for items: [SettingsViewModel.Section]) -> some View {
        ForEach(items) { item in
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(item.fill.gradient)
                    Image(systemName: item.systemImage)
                        .foregroundStyle(.white)
                        .font(.caption.weight(.semibold))
                }
                .frame(width: 22, height: 22)
                Text(item.title)
            }
            .tag(item)
        }
    }

    @ViewBuilder
    private func detailView(for section: SettingsViewModel.Section) -> some View {
        switch section {
        case .general:
            GeneralSettingsSection(viewModel: viewModel)
        case .model:
            ModelSettingsSection(viewModel: viewModel)
        case .shortcut:
            ShortcutSettingsSection(viewModel: viewModel)
        case .transcription:
            TranscriptionSettingsSection(viewModel: viewModel)
        case .permissions:
            PermissionsSettingsSection(viewModel: viewModel)
        case .history:
            HistorySettingsSection(viewModel: viewModel)
        case .about:
            AboutSettingsSection(viewModel: viewModel)
        }
    }
}

// MARK: - Previews

#Preview("General") {
    let viewModel = SettingsViewModel.makePreview()
    SettingsView(viewModel: viewModel)
        .frame(width: 980, height: 680)
}

#Preview("Smart Mode") {
    let viewModel = SettingsViewModel.makePreview { model in
        model.transcriptionMode = .smart
        model.smartPrompt = "Rewrite this into a concise action summary with bullet points."
        model.transcriptHistoryDays = [
            TranscriptHistoryDay(
                day: "2026-02-20",
                entries: [
                    TranscriptHistoryEntry(
                        id: UUID(),
                        timestamp: Date(),
                        transcript: "Schedule changed. Move standup to 10:30 and share notes after.",
                        modelID: model.selectedModelID,
                        transcriptionMode: model.transcriptionMode.rawValue,
                        audioDurationSeconds: 18.4,
                        transcriptionElapsedSeconds: 2.3,
                        characterCount: 78,
                        pasteResult: "success",
                        audioRelativePath: "2026-02-20/entry-1.wav",
                        transcriptRelativePath: "2026-02-20/entry-1.txt"
                    )
                ]
            )
        ]
    }

    viewModel.selectedSection = .transcription

    return SettingsView(viewModel: viewModel)
        .frame(width: 980, height: 680)
}

#Preview("Permissions Needed") {
    let viewModel = SettingsViewModel.makePreview { model in
        model.microphonePermissionState = .denied
        model.microphoneAuthorized = false
        model.accessibilityAuthorized = false
        model.lastError = "Enable microphone access in System Settings, then return to Gloam."
    }

    viewModel.selectedSection = .permissions

    return SettingsView(viewModel: viewModel)
        .frame(width: 980, height: 680)
}
