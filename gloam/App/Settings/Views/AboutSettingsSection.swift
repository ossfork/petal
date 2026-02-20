import AppKit
import SwiftUI
import UI

struct AboutSettingsSection: View {
    var viewModel: SettingsViewModel

    var body: some View {
        SettingsCard {
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

            LongButton("Check for Updates", symbol: "arrow.triangle.2.circlepath", variant: .secondary, verticalPadding: 8) {
                viewModel.checkForUpdates()
            }

            HStack(spacing: 12) {
                Link("aayush.art", destination: URL(string: "https://aayush.art")!)
                Link("GitHub", destination: URL(string: "https://github.com/Aayush9029")!)
            }
        }
    }
}
