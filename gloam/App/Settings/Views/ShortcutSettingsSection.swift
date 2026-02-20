import KeyboardShortcuts
import Shared
import SwiftUI

struct ShortcutSettingsSection: View {
    var viewModel: SettingsViewModel

    var body: some View {
        SettingsCard {
            KeyboardShortcuts.Recorder("Push-to-talk Shortcut", name: .pushToTalk)

            Text(viewModel.appModel.shortcutDisplayText)
                .font(.system(.caption, design: .monospaced))

            Text(viewModel.appModel.shortcutUsageText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
