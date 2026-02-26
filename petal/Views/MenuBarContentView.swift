import MacControlCenterUI
import Shared
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var viewModel: MenuBarContentViewModel

    @State private var isPresented = false

    var body: some View {
        MacControlCenterMenu(isPresented: $isPresented) {
            MenuSection("Status", divider: false)

            HStack {
                Label(viewModel.statusTitle, systemImage: viewModel.statusSymbolName)
                    .foregroundStyle(viewModel.statusColor)
                Spacer()
            }

            if let error = viewModel.statusErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let message = viewModel.transientMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.shouldShowPermissionsSection {
                MenuSection("Permissions")

                if viewModel.needsMicrophonePermission {
                    MenuCommand("Grant Microphone Access") {
                        viewModel.requestMicrophonePermission()
                    }
                }

                if viewModel.needsAccessibilityPermission {
                    MenuCommand("Enable Accessibility Access") {
                        viewModel.requestAccessibilityPermission()
                    }
                }
            }

            if viewModel.shouldShowHistoryMenu {
                MenuSection("History")

                Menu("Recent Transcripts") {
                    if viewModel.historyMenuItems.isEmpty {
                        Text("No transcripts yet")
                    } else {
                        ForEach(viewModel.historyMenuItems) { item in
                            Button {
                                viewModel.copyHistoryEntry(item.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                    Text(item.subtitle)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            MenuSection(divider: true) {
                if viewModel.showsCheckForUpdates {
                    MenuCommand("Check for Updates…") {
                        viewModel.checkForUpdates()
                    }
                    .disabled(!viewModel.canCheckForUpdates)
                }

                MenuCommand("About Petal") {
                    viewModel.showAbout()
                }

                MenuCommand("Settings…") {
                    viewModel.openSettings()
                }

                MenuCommand("Quit Petal") {
                    viewModel.quit()
                }
            }
        }
    }
}

#Preview("Ready") {
    let model = AppModel.makePreview()
    MenuBarContentView(viewModel: MenuBarContentViewModel(appModel: model))
}

#Preview("Needs Permissions") {
    let model = AppModel.makePreview { model in
        model.microphoneAuthorized = false
        model.accessibilityAuthorized = false
        model.transientMessage = "Permissions are required before recording."
    }

    MenuBarContentView(viewModel: MenuBarContentViewModel(appModel: model))
}

#Preview("With History") {
    let model = AppModel.makePreview { model in
        model.$transcriptHistoryDays.withLock { $0 = [
            TranscriptHistoryDay(
                day: "2026-02-20",
                entries: [
                    TranscriptHistoryEntry(
                        id: UUID(),
                        timestamp: Date(),
                        modelID: ModelOption.whisperLargeV3Turbo.rawValue,
                        audioDurationSeconds: 5.8,
                        audioRelativePath: "audio/clip1.m4a",
                        variants: [
                            TranscriptHistoryVariant(
                                mode: "smart",
                                transcriptionElapsedSeconds: 1.9,
                                characterCount: 57,
                                pasteResult: "pasted",
                                transcriptRelativePath: "transcripts/clip1.txt"
                            )
                        ]
                    )
                ]
            )
        ] }
    }

    MenuBarContentView(viewModel: MenuBarContentViewModel(appModel: model))
}
