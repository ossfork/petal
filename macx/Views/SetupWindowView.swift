import KeyboardShortcuts
import SwiftUI

struct SetupWindowView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("MacX Setup")
                .font(.title2.bold())

            Text(model.setupStepTitle)
                .font(.headline)

            Text(model.setupStepDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            setupStepper

            Group {
                switch model.setupStep {
                case .model:
                    modelStep
                case .shortcut:
                    shortcutStep
                case .download:
                    downloadStep
                }
            }

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let message = model.transientMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                if model.setupCanGoBack {
                    Button("Back") {
                        model.setupBackButtonTapped()
                    }
                }

                Button("Close") {
                    model.closeSetupWindowButtonTapped()
                }

                Spacer()

                Button(model.setupPrimaryButtonTitle) {
                    Task { await model.setupPrimaryButtonTapped() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.setupPrimaryButtonDisabled)
            }
        }
        .padding(24)
        .frame(width: 560, height: 500, alignment: .topLeading)
        .onAppear {
            model.setupWindowAppeared()
        }
        .onChange(of: model.selectedModelID) { _, _ in
            model.selectedModelSelectionChanged()
        }
    }

    private var setupStepper: some View {
        HStack(spacing: 10) {
            ForEach(model.setupStepItems, id: \.rawValue) { step in
                HStack(spacing: 6) {
                    Image(systemName: symbolName(for: step))
                        .font(.caption.weight(.semibold))

                    Text(model.setupStepDisplayName(step))
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(stepBackground(step), in: Capsule())
                .foregroundStyle(stepForeground(step))
            }
        }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model")
                .font(.headline)

            Picker("Model", selection: $model.selectedModelID) {
                ForEach(ModelOption.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.radioGroup)

            if let option = model.selectedModelOption {
                Label("\(option.sizeLabel) - \(option.summary)", systemImage: "externaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Push-to-talk Shortcut")
                .font(.headline)

            KeyboardShortcuts.Recorder("Shortcut", name: .pushToTalk)

            Text(model.shortcutDisplayText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(model.shortcutUsageText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var downloadStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selected model")
                    .font(.headline)

                Text(model.currentModelSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                permissionRow(
                    title: "Microphone",
                    isGranted: model.microphoneAuthorized,
                    actionTitle: "Grant",
                    action: microphonePermissionButtonTapped
                )

                permissionRow(
                    title: "Accessibility",
                    isGranted: model.accessibilityAuthorized,
                    actionTitle: "Enable",
                    action: accessibilityPermissionButtonTapped
                )

                Text("Accessibility is optional, but needed for auto-paste into the focused app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("Downloader: aria2c", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Models folder: \(model.modelsDirectoryDisplayPath)", systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Save history to disk", isOn: $model.saveHistory)
                    .font(.caption)

                Label("History folder: \(model.historyDirectoryDisplayPath)", systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Button("Open History Folder") {
                    model.openHistoryFolderButtonTapped()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            if model.isDownloadingModel || model.downloadProgress > 0 || !model.downloadStatus.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.downloadStatus.isEmpty ? "Download status" : model.downloadStatus)
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text(model.setupDownloadSummaryText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: model.downloadProgress)
                }
            }
        }
    }

    private func permissionRow(title: String, isGranted: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: isGranted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isGranted ? .green : .secondary)

            Spacer()

            if !isGranted {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
    }

    private func symbolName(for step: AppModel.SetupStep) -> String {
        if step.rawValue < model.setupStep.rawValue {
            return "checkmark.circle.fill"
        }

        switch step {
        case .model:
            return "1.circle.fill"
        case .shortcut:
            return "2.circle.fill"
        case .download:
            return "3.circle.fill"
        }
    }

    private func stepBackground(_ step: AppModel.SetupStep) -> some ShapeStyle {
        if step == model.setupStep {
            return AnyShapeStyle(Color.accentColor.opacity(0.18))
        }

        if step.rawValue < model.setupStep.rawValue {
            return AnyShapeStyle(Color.green.opacity(0.14))
        }

        return AnyShapeStyle(Color.secondary.opacity(0.12))
    }

    private func stepForeground(_ step: AppModel.SetupStep) -> some ShapeStyle {
        if step == model.setupStep {
            return AnyShapeStyle(Color.accentColor)
        }

        if step.rawValue < model.setupStep.rawValue {
            return AnyShapeStyle(Color.green)
        }

        return AnyShapeStyle(Color.secondary)
    }

    private func microphonePermissionButtonTapped() {
        Task { await model.microphonePermissionButtonTapped() }
    }

    private func accessibilityPermissionButtonTapped() {
        model.accessibilityPermissionButtonTapped()
    }
}

#if DEBUG
@MainActor
private func makeSetupPreviewModel(
    step: AppModel.SetupStep,
    configure: (AppModel) -> Void = { _ in }
) -> AppModel {
    AppModel.makePreview { model in
        model.hasCompletedSetup = false
        model.setupStep = step
        configure(model)
    }
}

#Preview("Step 1 - Model") {
    SetupWindowView(model: makeSetupPreviewModel(step: .model))
}

#Preview("Step 2 - Shortcut") {
    SetupWindowView(model: makeSetupPreviewModel(step: .shortcut))
}

#Preview("Step 3 - Permissions") {
    SetupWindowView(
        model: makeSetupPreviewModel(step: .download) { model in
            model.microphonePermissionState = .notDetermined
            model.microphoneAuthorized = false
            model.accessibilityAuthorized = false
            model.transientMessage = "Grant permissions, then download your selected model."
        }
    )
}

#Preview("Step 3 - Downloading") {
    SetupWindowView(
        model: makeSetupPreviewModel(step: .download) { model in
            model.microphonePermissionState = .authorized
            model.microphoneAuthorized = true
            model.accessibilityAuthorized = true
            model.isDownloadingModel = true
            model.downloadProgress = 0.42
            model.downloadStatus = "Downloading model…"
            model.downloadSpeedText = "11.2 MB/s"
        }
    )
}
#endif
