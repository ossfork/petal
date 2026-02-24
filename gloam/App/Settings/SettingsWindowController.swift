import AppKit
import SwiftUI

struct SettingsPane: Identifiable {
    let id: String
    let title: String
    let icon: String
    let view: () -> AnyView

    init<V: View>(id: String, title: String, icon: String, @ViewBuilder view: @escaping () -> V) {
        self.id = id
        self.title = title
        self.icon = icon
        self.view = { AnyView(view()) }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let panes: [SettingsPane]
    private var selectedPaneID: String
    private var hostingController: NSHostingController<AnyView>?

    init(viewModel: SettingsViewModel, updatesModel: CheckForUpdatesModel?) {
        let panes = [
            SettingsPane(id: "general", title: "General", icon: "gearshape") {
                GeneralPane(viewModel: viewModel)
            },
            SettingsPane(id: "transcription", title: "Transcription", icon: "waveform") {
                TranscriptionPane(viewModel: viewModel)
            },
            SettingsPane(id: "history", title: "History", icon: "clock") {
                HistoryPane(viewModel: viewModel)
            },
            SettingsPane(id: "about", title: "About", icon: "info.circle") {
                AboutPane(updatesModel: updatesModel)
            },
        ]

        self.panes = panes
        self.selectedPaneID = panes[0].id

        let hosting = NSHostingController(rootView: panes[0].view())
        self.hostingController = hosting

        let window = NSWindow(contentViewController: hosting)
        window.title = panes[0].title
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

        selectPane(panes[0].id)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func selectPane(_ paneID: String) {
        guard let pane = panes.first(where: { $0.id == paneID }) else { return }
        selectedPaneID = pane.id
        window?.title = pane.title

        let newHosting = NSHostingController(rootView: pane.view())
        hostingController = newHosting
        window?.contentViewController = newHosting

        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(pane.id)
    }

    // MARK: - NSToolbarDelegate

    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        MainActor.assumeIsolated {
            panes.map { NSToolbarItem.Identifier($0.id) }
        }
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
            guard let pane = panes.first(where: { $0.id == itemIdentifier.rawValue }) else { return nil }

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
