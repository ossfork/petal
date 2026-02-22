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
                Text(viewModel.appModel.statusTitle)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)
            }

            SettingsSection("Permissions", bottomDivider: true, verticalAlignment: .center) {
                HStack(spacing: 16) {
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
                }
                .fixedSize()

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

                Text(viewModel.appModel.historyDirectoryDisplayPath)
                    .settingDescription()
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("Open in Finder") {
                    viewModel.openHistoryFolder()
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch viewModel.appModel.sessionState {
        case .idle:
            return viewModel.appModel.hasCompletedSetup ? .green : .orange
        case .recording:
            return .red
        case .processing:
            return .orange
        case .error:
            return .red
        }
    }

    private func permissionRow(
        _ title: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: isGranted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isGranted ? .green : .secondary)

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
                .frame(width: 200)

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
            SettingsSection("Model") {
                if let option = viewModel.modelDownloadViewModel.selectedModelOption {
                    Text(option.displayName)
                        .fontWeight(.medium)

                    Text(option.summary)
                        .settingDescription()

                    HStack(spacing: 6) {
                        Text(option.sizeLabel)
                            .foregroundStyle(.secondary)
                        Text("\u{00B7}")
                            .foregroundStyle(.tertiary)
                        Text(downloadStatusText)
                            .foregroundStyle(downloadStatusColor)
                    }
                    .font(.caption)
                }

                if viewModel.modelDownloadViewModel.isDownloadingModel {
                    ProgressView(value: viewModel.modelDownloadViewModel.downloadProgress)
                        .frame(maxWidth: 300)

                    Text(viewModel.modelDownloadViewModel.downloadSummaryText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let downloadError = viewModel.modelDownloadViewModel.lastError {
                    Text(downloadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Helpers

    private var downloadStatusText: String {
        let dm = viewModel.modelDownloadViewModel
        if dm.isDownloadingModel {
            return dm.downloadStatus.isEmpty ? "Downloading\u{2026}" : dm.downloadStatus
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
                        HStack {
                            Text("Push-to-talk")
                            Spacer(minLength: 0)
                            KeyboardShortcuts.Recorder(for: .pushToTalk)
                        }
                        .frame(width: 400)
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    Text(viewModel.appModel.shortcutUsageText)
                        .settingDescription()
                        .multilineTextAlignment(.center)
                    Spacer()
                }
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
                HStack {
                    Spacer()
                    VStack(alignment: .center, spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 14))

                        VStack(spacing: 2) {
                            Text("Gloam")
                                .font(.title3.weight(.semibold))
                            Text(viewModel.versionText)
                                .foregroundStyle(.secondary)
                        }

                        Button("Check for Updates") {
                            viewModel.checkForUpdates()
                        }
                        .controlSize(.small)

                        HStack(spacing: 12) {
                            Link("aayush.art", destination: URL(string: "https://aayush.art")!)
                            Link("GitHub", destination: URL(string: "https://github.com/Aayush9029")!)
                        }
                    }
                    Spacer()
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
