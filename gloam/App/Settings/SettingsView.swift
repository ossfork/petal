import KeyboardShortcuts
import Shared
import Sparkle
import SwiftUI

// MARK: - General Pane

struct GeneralPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Push to Talk") {
                    KeyboardShortcuts.Recorder(for: .pushToTalk)
                }
                Text("Tap to toggle recording, or hold and release to stop.")
                    .settingDescription()
            }

            Section("Permissions") {
                LabeledContent("Microphone") {
                    if viewModel.microphoneAuthorized {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            viewModel.grantMicrophonePermission()
                        }
                    }
                }

                LabeledContent("Accessibility") {
                    if viewModel.accessibilityAuthorized {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            viewModel.grantAccessibilityPermission()
                        }
                    }
                }

                if let message = viewModel.permissionMessage {
                    Text(message)
                        .settingDescription()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .task {
            await viewModel.refreshPermissions()
        }
    }
}

// MARK: - Transcription Pane

struct TranscriptionPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Model") {
                Picker("Model", selection: Binding(
                    get: { viewModel.selectedModelID },
                    set: { viewModel.selectedModelID = $0 }
                )) {
                    ForEach(ModelOption.allCases) { option in
                        HStack {
                            Text(option.displayName)
                            if option.isRecommended {
                                Text("Recommended")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(option.rawValue)
                    }
                }

                if let model = viewModel.selectedModelOption {
                    LabeledContent("Provider") {
                        Text(model.providerDisplayName)
                    }
                    LabeledContent("Size") {
                        Text(model.sizeLabel)
                    }
                }

                if viewModel.isSelectedModelDownloaded {
                    LabeledContent("Status") {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else if viewModel.isDownloadingModel {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: viewModel.downloadProgress)
                        Text(viewModel.downloadSummaryText)
                            .settingDescription()
                    }
                    Button("Cancel") {
                        viewModel.cancelDownload()
                    }
                } else {
                    Button("Download Model") {
                        viewModel.downloadModel()
                    }
                }

                if let error = viewModel.downloadError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Audio Preprocessing") {
                Toggle("Trim silence", isOn: Binding(
                    get: { viewModel.trimSilenceEnabled },
                    set: { viewModel.trimSilenceEnabled = $0 }
                ))
                Toggle("Auto speed-up", isOn: Binding(
                    get: { viewModel.autoSpeedEnabled },
                    set: { viewModel.autoSpeedEnabled = $0 }
                ))
                Text("Remove leading/trailing silence and speed up quiet audio before transcription.")
                    .settingDescription()
            }

            if viewModel.selectedModelOption?.supportsSmartTranscription == true {
                Section("Mode") {
                    Picker("Transcription Mode", selection: Binding(
                        get: { viewModel.transcriptionMode },
                        set: { viewModel.transcriptionMode = $0 }
                    )) {
                        ForEach(TranscriptionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(viewModel.transcriptionMode.description)
                        .settingDescription()
                }

                if viewModel.transcriptionMode == .smart {
                    Section("Smart Prompt") {
                        TextField("Prompt", text: Binding(
                            get: { viewModel.smartPrompt },
                            set: { viewModel.smartPrompt = $0 }
                        ), axis: .vertical)
                        .lineLimit(3...6)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
    }
}

// MARK: - History Pane

struct HistoryPane: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Retention") {
                Picker("Keep", selection: Binding(
                    get: { viewModel.historyRetentionMode },
                    set: { viewModel.historyRetentionMode = $0 }
                )) {
                    ForEach(HistoryRetentionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Compression") {
                Toggle("Compress audio", isOn: Binding(
                    get: { viewModel.compressHistoryAudio },
                    set: { viewModel.compressHistoryAudio = $0 }
                ))
                Text("Convert saved audio to AAC to save disk space.")
                    .settingDescription()
            }

            Section("Storage") {
                LabeledContent("Location") {
                    Text(viewModel.historyDirectoryPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Open in Finder") {
                    viewModel.openHistoryInFinder()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
    }
}

// MARK: - About Pane

struct AboutPane: View {
    var updatesModel: CheckForUpdatesModel?

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("Gloam")
                .font(.title2.bold())

            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)

            if let updatesModel {
                Button("Check for Updates…") {
                    updatesModel.checkForUpdates()
                }
                .disabled(!updatesModel.canCheckForUpdates)
            }

            HStack(spacing: 16) {
                Link("aayush.art", destination: URL(string: "https://aayush.art")!)
                Link("GitHub", destination: URL(string: "https://github.com/Aayush9029/gloam")!)
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(width: 540, height: 300)
    }
}

// MARK: - Helpers

private extension View {
    func settingDescription() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
    }
}
