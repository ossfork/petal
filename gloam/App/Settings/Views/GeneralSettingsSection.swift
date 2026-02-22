import SwiftUI
import UI

struct GeneralSettingsSection: View {
    var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
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
                    LongButton("Open Onboarding", symbol: "arrow.right.circle") {
                        viewModel.openSetupAssistant()
                    }

                    LongButton("Open History Folder", symbol: "folder") {
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
}
