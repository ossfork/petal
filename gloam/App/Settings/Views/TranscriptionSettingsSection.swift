import Shared
import SwiftUI

struct TranscriptionSettingsSection: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsCard {
            Picker("Mode", selection: transcriptionMode) {
                ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.appModel.transcriptionMode.description)
                .foregroundStyle(.secondary)

            if viewModel.appModel.transcriptionMode == .smart {
                Divider()

                Text("Smart Prompt")
                    .font(.headline)

                TextField("Custom instruction…", text: smartPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)
            }
        }
    }

    // MARK: - Bindings

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
