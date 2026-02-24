import KeyboardShortcuts
import Shared
import SwiftUI

// MARK: - Settings Root

struct SettingsView: View {
    @State var selectedTab: SettingsTab = .general
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralPane(viewModel: viewModel)
            }
            Tab("Transcription", systemImage: "waveform", value: .transcription) {
                TranscriptionPane(viewModel: viewModel)
            }
            Tab("History", systemImage: "clock", value: .history) {
                HistoryPane(viewModel: viewModel)
            }
        }
    }
}

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
                            Task { await viewModel.grantMicrophonePermissionButtonTapped() }
                        }
                    }
                }

                LabeledContent("Accessibility") {
                    if viewModel.accessibilityAuthorized {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            Task { await viewModel.grantAccessibilityPermissionButtonTapped() }
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
                } else if viewModel.isDownloadingModel || viewModel.isPaused {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: viewModel.downloadProgress)
                        if !viewModel.downloadStatus.isEmpty {
                            Text(viewModel.downloadStatus)
                                .settingDescription()
                        }
                        Text(viewModel.downloadSummaryText)
                            .settingDescription()
                    }
                    HStack {
                        if viewModel.isPaused {
                            Button("Resume") {
                                Task { await viewModel.resumeButtonTapped() }
                            }
                        } else {
                            Button("Pause") {
                                viewModel.pauseButtonTapped()
                            }
                        }

                        Button("Cancel") {
                            viewModel.cancelButtonTapped()
                        }
                    }
                } else {
                    Button("Download Model") {
                        Task { await viewModel.downloadButtonTapped() }
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
    }
}

// MARK: - Helpers

private extension View {
    func settingDescription() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
    }
}
