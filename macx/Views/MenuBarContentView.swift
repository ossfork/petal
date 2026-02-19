import KeyboardShortcuts
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.statusTitle, systemImage: model.menuBarSymbolName)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Shortcut")
                    .font(.subheadline.weight(.semibold))
                KeyboardShortcuts.Recorder("Push to talk", name: .pushToTalk)
                Text(model.shortcutDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.shortcutUsageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.subheadline.weight(.semibold))
                Text(model.currentModelSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(model.hasCompletedSetup ? "Change Model…" : "Complete Setup…") {
                    model.changeModelButtonTapped()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Mode")
                    .font(.subheadline.weight(.semibold))

                Picker("Mode", selection: $model.transcriptionMode) {
                    ForEach(TranscriptionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(model.transcriptionMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.transcriptionMode == .smart {
                    TextField("Custom instruction…", text: $model.smartPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .lineLimit(2...4)
                }
            }

            Divider()

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
            }

            if let message = model.transientMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Quit MacX") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 320)
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

    private func microphonePermissionButtonTapped() {
        Task { await model.microphonePermissionButtonTapped() }
    }

    private func accessibilityPermissionButtonTapped() {
        model.accessibilityPermissionButtonTapped()
    }
}

#if DEBUG
#Preview("Ready") {
    MenuBarContentView(model: .makePreview())
        .padding()
}

#Preview("Setup Required") {
    MenuBarContentView(
        model: .makePreview { model in
            model.hasCompletedSetup = false
            model.microphonePermissionState = .notDetermined
            model.microphoneAuthorized = false
            model.accessibilityAuthorized = false
            model.transientMessage = "Complete setup to start recording."
        }
    )
    .padding()
}

#Preview("Recording") {
    MenuBarContentView(
        model: .makePreview { model in
            model.sessionState = .recording
            model.transientMessage = "Listening... press shortcut again to stop."
        }
    )
    .padding()
}
#endif
