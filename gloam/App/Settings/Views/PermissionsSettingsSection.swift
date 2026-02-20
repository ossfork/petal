import SwiftUI

struct PermissionsSettingsSection: View {
    var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
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
}
