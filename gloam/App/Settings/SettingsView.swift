import AppKit
import KeyboardShortcuts
import Onboarding
import PermissionsClient
import Shared
import SwiftUI
import UI

// MARK: - General

struct GeneralPane: View {
    var viewModel: SettingsViewModel

    var body: some View {
        SettingsContainer {
            SettingsSection("Status", bottomDivider: true) {
                LabeledContent("Status") {
                    Text(viewModel.appModel.statusTitle)
                        .fontWeight(.medium)
                }
                LabeledContent("Current Model") {
                    Text(viewModel.appModel.currentModelSummary)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("Permissions", bottomDivider: true) {
                permissionRow(
                    "Microphone",
                    isGranted: viewModel.appModel.microphoneAuthorized,
                    action: viewModel.requestMicrophonePermission
                )
                permissionRow(
                    "Accessibility",
                    isGranted: viewModel.appModel.accessibilityAuthorized,
                    action: viewModel.requestAccessibilityPermission
                )

                if let message = viewModel.settingsMessage {
                    Text(message).settingDescription()
                }
            }

            SettingsSection("History") {
                Picker("Retention", selection: historyRetentionMode) {
                    ForEach(HistoryRetentionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .fixedSize()

                HStack(spacing: 8) {
                    Text(viewModel.appModel.historyDirectoryDisplayPath)
                        .settingDescription()
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Open Folder") {
                        viewModel.openHistoryFolder()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Helpers

    private func permissionRow(
        _ title: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(title, systemImage: isGranted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isGranted ? .green : .secondary)

            Spacer()

            if !isGranted {
                Button("Grant", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var historyRetentionMode: Binding<HistoryRetentionMode> {
        Binding(
            get: { viewModel.appModel.historyRetentionMode },
            set: { viewModel.appModel.historyRetentionMode = $0 }
        )
    }
}

// MARK: - Transcription

struct TranscriptionPane: View {
    var viewModel: SettingsViewModel

    var body: some View {
        SettingsContainer {
            SettingsSection("Mode", bottomDivider: viewModel.appModel.transcriptionMode == .smart) {
                Picker("Mode", selection: transcriptionMode) {
                    ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                Text(viewModel.appModel.transcriptionMode.description)
                    .settingDescription()
            }

            if viewModel.appModel.transcriptionMode == .smart {
                SettingsSection("Smart Prompt") {
                    TextField("Custom instruction…", text: smartPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(4...8)
                }
            }
        }
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
}

// MARK: - Model

struct ModelPane: View {
    var viewModel: SettingsViewModel

    var body: some View {
        SettingsContainer {
            SettingsSection(bottomDivider: true, label: { EmptyView() }) {
                Picker("Selected Model", selection: selectedModelID) {
                    ForEach(ModelOption.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .fixedSize()

                if let option = viewModel.modelDownloadViewModel.selectedModelOption {
                    Text(option.summary)
                        .settingDescription()

                    LabeledContent("Model Size") {
                        Text(option.sizeLabel)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Download") {
                    Text(downloadStatusText)
                        .foregroundStyle(downloadStatusColor)
                }

                if shouldShowProgress {
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
            }

            SettingsSection(label: { EmptyView() }) {
                HStack(spacing: 10) {
                    Button(downloadButtonTitle) {
                        viewModel.downloadModel()
                    }
                    .disabled(
                        viewModel.modelDownloadViewModel.isDownloadingModel
                            || viewModel.modelDownloadViewModel.isSelectedModelDownloaded
                    )

                    Button("Setup Assistant") {
                        viewModel.openSetupAssistant()
                    }
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    private var selectedModelID: Binding<String> {
        Binding(
            get: { viewModel.modelDownloadViewModel.selectedModelID },
            set: { viewModel.selectModel($0) }
        )
    }

    private var shouldShowProgress: Bool {
        let dm = viewModel.modelDownloadViewModel
        return dm.isDownloadingModel
            || dm.downloadProgress > 0
            || !dm.downloadStatus.isEmpty
    }

    private var downloadButtonTitle: String {
        let dm = viewModel.modelDownloadViewModel
        if dm.isDownloadingModel { return "Downloading…" }
        if dm.isSelectedModelDownloaded { return "Downloaded" }
        return "Download Model"
    }

    private var downloadStatusText: String {
        let dm = viewModel.modelDownloadViewModel
        if dm.isDownloadingModel {
            return dm.downloadStatus.isEmpty ? "Downloading…" : dm.downloadStatus
        }
        if dm.lastError != nil { return "Failed" }
        if dm.isSelectedModelDownloaded { return "Downloaded" }
        if !dm.downloadStatus.isEmpty { return dm.downloadStatus }
        return "Not Downloaded"
    }

    private var downloadStatusColor: Color {
        let dm = viewModel.modelDownloadViewModel
        if dm.isDownloadingModel { return .blue }
        if dm.lastError != nil { return .red }
        if dm.isSelectedModelDownloaded { return .green }
        return .orange
    }
}

// MARK: - Shortcut

struct ShortcutPane: View {
    var viewModel: SettingsViewModel

    var body: some View {
        SettingsContainer {
            SettingsSection(label: { EmptyView() }) {
                HStack {
                    GroupBackground {
                        VStack(alignment: .center, spacing: 12) {
                            HStack {
                                Text("Push-to-talk")
                                Spacer(minLength: 0)
                                KeyboardShortcuts.Recorder(for: .pushToTalk)
                            }
                        }
                        .frame(width: 400)
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity)

                Text(viewModel.appModel.shortcutUsageText)
                    .settingDescription()
            }
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var viewModel: SettingsViewModel

    var body: some View {
        SettingsContainer {
            SettingsSection(label: { EmptyView() }) {
                HStack(spacing: 12) {
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
                }
                .padding(.bottom, 8)

                Button("Check for Updates") {
                    viewModel.checkForUpdates()
                }
                .controlSize(.small)

                HStack(spacing: 12) {
                    Link("aayush.art", destination: URL(string: "https://aayush.art")!)
                    Link("GitHub", destination: URL(string: "https://github.com/Aayush9029")!)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("General") {
    GeneralPane(viewModel: .makePreview())
}

#Preview("Transcription – Smart") {
    let vm = SettingsViewModel.makePreview { model in
        model.transcriptionMode = .smart
        model.smartPrompt = "Rewrite this into a concise action summary with bullet points."
    }
    TranscriptionPane(viewModel: vm)
}

#Preview("Model") {
    ModelPane(viewModel: .makePreview())
}

#Preview("Shortcut") {
    ShortcutPane(viewModel: .makePreview())
}

#Preview("About") {
    AboutPane(viewModel: .makePreview())
}
