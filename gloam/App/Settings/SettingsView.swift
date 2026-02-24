import Assets
import KeyboardShortcuts
import ModelDownloadFeature
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
        ScrollView {
            Form {
                Section("Model") {
                    Picker("Model", selection: Binding(
                        get: { viewModel.selectedModelID },
                        set: { viewModel.selectedModelID = $0 }
                    )) {
                        ForEach(ModelOption.allCases) { option in
                            HStack {
                                providerIcon(for: option)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
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

                    if let model = viewModel.downloadModel.selectedModelOption {
                        LabeledContent("Provider") {
                            HStack(spacing: 6) {
                                providerIcon(for: model)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                Text(model.providerDisplayName)
                            }
                        }
                        LabeledContent("Size") {
                            Text(model.sizeLabel)
                        }
                    }

                    modelDownloadStatus
                }

                Section("Audio Preprocessing") {
                    Toggle("Trim silence", isOn: Binding(viewModel.$trimSilenceEnabled))
                    Toggle("Auto speed-up", isOn: Binding(viewModel.$autoSpeedEnabled))
                    Text("Remove leading/trailing silence and speed up quiet audio before transcription.")
                        .settingDescription()
                }

                if viewModel.downloadModel.selectedModelOption?.supportsSmartTranscription == true {
                    Section("Mode") {
                        Picker("Transcription Mode", selection: Binding(viewModel.$transcriptionMode)) {
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
                            TextField("Prompt", text: Binding(viewModel.$smartPrompt), axis: .vertical)
                            .lineLimit(3...6)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func providerIcon(for option: ModelOption) -> Image {
        switch option.provider {
        case .mlxAudioSTT: .qwen
        case .whisperKit: .openai
        case .voxtralCore: .mistral
        }
    }

    @ViewBuilder
    private var modelDownloadStatus: some View {
        switch viewModel.downloadModel.state {
        case .downloaded:
            LabeledContent("Status") {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case let .downloading(progress):
            downloadProgressSection(progress: progress, isPaused: false)
        case let .paused(progress):
            downloadProgressSection(progress: progress, isPaused: true)
        case .notDownloaded, .preparing:
            Button("Download Model") {
                Task { await viewModel.downloadButtonTapped() }
            }
        case let .failed(message):
            Button("Download Model") {
                Task { await viewModel.downloadButtonTapped() }
            }
            Text(message)
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func downloadProgressSection(progress: ModelDownloadState.Progress, isPaused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress.fraction)
            if !progress.statusText.isEmpty {
                Text(progress.statusText)
                    .settingDescription()
            }
            Text(progress.summaryText)
                .settingDescription()
        }
        HStack {
            if isPaused {
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
                    set: { viewModel.historyRetentionModeChanged($0) }
                )) {
                    ForEach(HistoryRetentionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            Section("Compression") {
                Toggle("Compress audio", isOn: Binding(viewModel.$compressHistoryAudio))
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
