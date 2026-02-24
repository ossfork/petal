import AppKit
import SwiftUI

@MainActor
@Observable
final class SettingsNavigation {
    var selectedPaneID: String = "general"

    struct PaneDescriptor {
        let id: String
        let title: String
        let icon: String
    }

    static let panes: [PaneDescriptor] = [
        PaneDescriptor(id: "general", title: "General", icon: "gearshape"),
        PaneDescriptor(id: "transcription", title: "Transcription", icon: "waveform"),
        PaneDescriptor(id: "history", title: "History", icon: "clock"),
        PaneDescriptor(id: "about", title: "About", icon: "info.circle"),
    ]
}

struct SettingsRootView: View {
    @Bindable var navigation: SettingsNavigation
    var viewModel: SettingsViewModel
    var updatesModel: CheckForUpdatesModel?

    var body: some View {
        Group {
            switch navigation.selectedPaneID {
            case "general":
                GeneralPane(viewModel: viewModel)
            case "transcription":
                TranscriptionPane(viewModel: viewModel)
            case "history":
                HistoryPane(viewModel: viewModel)
            case "about":
                AboutPane(updatesModel: updatesModel)
            default:
                GeneralPane(viewModel: viewModel)
            }
        }
        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let navigation: SettingsNavigation

    init(viewModel: SettingsViewModel, updatesModel: CheckForUpdatesModel?) {
        let navigation = SettingsNavigation()
        self.navigation = navigation

        let rootView = SettingsRootView(
            navigation: navigation,
            viewModel: viewModel,
            updatesModel: updatesModel
        )
        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hosting)
        window.title = "General"
        window.styleMask = [.titled, .closable]
        window.identifier = NSUserInterfaceItemIdentifier("GloamSettingsWindow")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(NSSize(width: 540, height: 400))
        window.center()

        super.init(window: window)

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier("general")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func selectPane(_ paneID: String) {
        guard let pane = SettingsNavigation.panes.first(where: { $0.id == paneID }) else { return }
        navigation.selectedPaneID = pane.id
        window?.title = pane.title
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(pane.id)
    }

    // MARK: - NSToolbarDelegate

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsNavigation.panes.map { NSToolbarItem.Identifier($0.id) }
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    nonisolated func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    nonisolated func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        MainActor.assumeIsolated {
            guard let pane = SettingsNavigation.panes.first(where: { $0.id == itemIdentifier.rawValue }) else { return nil }

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.icon, accessibilityDescription: pane.title)
            item.target = self
            item.action = #selector(toolbarItemTapped(_:))
            return item
        }
    }

    @objc private func toolbarItemTapped(_ sender: NSToolbarItem) {
        selectPane(sender.itemIdentifier.rawValue)
    }
}
