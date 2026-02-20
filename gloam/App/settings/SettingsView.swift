import AppKit
import KeyboardShortcuts
import Onboarding
import PermissionsClient
import Shared
import SwiftUI

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
            Label(item.title, systemImage: item.systemImage)
                .tag(item)
        }
    }

    @ViewBuilder
    private func detailView(for section: SettingsViewModel.Section) -> some View {
        switch section {
        case .general:
            generalSection
        case .model:
            modelSection
        case .shortcut:
            shortcutSection
        case .transcription:
            transcriptionSection
        case .permissions:
            permissionsSection
        case .history:
            historySection
        case .about:
            aboutSection
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsCard {
                LabeledContent("Status") {
                    Text(viewModel.appModel.statusTitle)
                        .fontWeight(.semibold)
                }

                Divider()

                LabeledContent("Current Model") {
                    Text(viewModel.appModel.currentModelSummary)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: 10) {
                    Button("Open Onboarding") {
                        viewModel.openSetupAssistant()
                    }

                    Button("Open History Folder") {
                        viewModel.openHistoryFolder()
                    }
                }
            }

            if let message = viewModel.settingsMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var modelSection: some View {
        settingsCard {
            Picker("Selected Model", selection: selectedModelID) {
                ForEach(ModelOption.allCases, id: \.rawValue) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }

            Divider()

            if let option = viewModel.modelDownloadViewModel.selectedModelOption {
                Text(option.summary)
                    .foregroundStyle(.secondary)

                LabeledContent("Model Size") {
                    Text(option.sizeLabel)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Download Status") {
                Text(modelDownloadStatusText)
                    .foregroundStyle(modelDownloadStatusColor)
            }

            if shouldShowDownloadProgress {
                ProgressView(value: viewModel.modelDownloadViewModel.downloadProgress)

                HStack {
                    Text(viewModel.modelDownloadViewModel.downloadSummaryText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let speedText = viewModel.modelDownloadViewModel.downloadSpeedText {
                        Text(speedText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let downloadError = viewModel.modelDownloadViewModel.lastError {
                Text(downloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 10) {
                Button(downloadButtonTitle) {
                    viewModel.downloadModel()
                }
                .disabled(viewModel.modelDownloadViewModel.isDownloadingModel || viewModel.modelDownloadViewModel.isSelectedModelDownloaded)

                Button("Open Setup Assistant") {
                    viewModel.openSetupAssistant()
                }
            }
        }
    }

    private var shortcutSection: some View {
        settingsCard {
            KeyboardShortcuts.Recorder("Push-to-talk Shortcut", name: .pushToTalk)

            Text(viewModel.appModel.shortcutDisplayText)
                .font(.system(.caption, design: .monospaced))

            Text(viewModel.appModel.shortcutUsageText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var transcriptionSection: some View {
        settingsCard {
            Picker("Mode", selection: transcriptionMode) {
                ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.appModel.transcriptionMode.description)
                .foregroundStyle(.secondary)

            if viewModel.appModel.transcriptionMode == .smart {
                Divider()

                Text("Smart Prompt")
                    .font(.headline)

                TextField("Custom instruction…", text: smartPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)
            }
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsCard {
                permissionRow(
                    title: "Microphone",
                    isGranted: viewModel.appModel.microphoneAuthorized,
                    actionTitle: "Grant",
                    action: viewModel.requestMicrophonePermission
                )

                Divider()

                permissionRow(
                    title: "Accessibility",
                    isGranted: viewModel.appModel.accessibilityAuthorized,
                    actionTitle: "Enable",
                    action: viewModel.requestAccessibilityPermission
                )
            }

            if let message = viewModel.settingsMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsCard {
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

            settingsCard {
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

    private var aboutSection: some View {
        settingsCard {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Gloam")
                        .font(.title3.weight(.semibold))
                    Text(viewModel.versionText)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 12) {
                Button("Check for Updates") {
                    viewModel.checkForUpdates()
                }

                Link("aayush.art", destination: URL(string: "https://aayush.art")!)
                Link("GitHub", destination: URL(string: "https://github.com/Aayush9029")!)
            }
        }
    }

    private func permissionRow(
        title: String,
        isGranted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(title, systemImage: isGranted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isGranted ? .green : .secondary)

            Spacer()

            if !isGranted {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var selectedModelID: Binding<String> {
        Binding(
            get: { viewModel.modelDownloadViewModel.selectedModelID },
            set: { viewModel.selectModel($0) }
        )
    }

    private var shouldShowDownloadProgress: Bool {
        let downloadModel = viewModel.modelDownloadViewModel
        return downloadModel.isDownloadingModel
            || downloadModel.downloadProgress > 0
            || !downloadModel.downloadStatus.isEmpty
    }

    private var downloadButtonTitle: String {
        let downloadModel = viewModel.modelDownloadViewModel

        if downloadModel.isDownloadingModel {
            return "Downloading..."
        }

        if downloadModel.isSelectedModelDownloaded {
            return "Downloaded"
        }

        return "Download Model"
    }

    private var modelDownloadStatusText: String {
        let downloadModel = viewModel.modelDownloadViewModel

        if downloadModel.isDownloadingModel {
            return downloadModel.downloadStatus.isEmpty ? "Downloading..." : downloadModel.downloadStatus
        }

        if downloadModel.lastError != nil {
            return "Failed"
        }

        if downloadModel.isSelectedModelDownloaded {
            return "Downloaded"
        }

        if !downloadModel.downloadStatus.isEmpty {
            return downloadModel.downloadStatus
        }

        return "Not Downloaded"
    }

    private var modelDownloadStatusColor: Color {
        let downloadModel = viewModel.modelDownloadViewModel

        if downloadModel.isDownloadingModel {
            return .blue
        }

        if downloadModel.lastError != nil {
            return .red
        }

        if downloadModel.isSelectedModelDownloaded {
            return .green
        }

        return .orange
    }

    private var transcriptionMode: Binding<TranscriptionMode> {
        Binding(
            get: { viewModel.appModel.transcriptionMode },
            set: { viewModel.appModel.transcriptionMode = $0 }
        )
    }

    private var smartPrompt: Binding<String> {
        Binding(
            get: { viewModel.appModel.smartPrompt },
            set: { viewModel.appModel.smartPrompt = $0 }
        )
    }

    private var historyRetentionMode: Binding<HistoryRetentionMode> {
        Binding(
            get: { viewModel.appModel.historyRetentionMode },
            set: { viewModel.appModel.historyRetentionMode = $0 }
        )
    }
}

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
