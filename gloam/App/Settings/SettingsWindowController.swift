import AppKit
import KeyboardShortcuts
import Onboarding
import Shared
import SwiftUI
import UI

// MARK: - SettingsPane Protocol

protocol SettingsPane: NSViewController {
    var paneIdentifier: NSToolbarItem.Identifier { get }
    var paneTitle: String { get }
    var toolbarItemIcon: NSImage { get }
}

// MARK: - PaneHostingController

final class PaneHostingController<Content: View>: NSHostingController<Content>, SettingsPane {
    let paneIdentifier: NSToolbarItem.Identifier
    let paneTitle: String
    let toolbarItemIcon: NSImage

    init(identifier: NSToolbarItem.Identifier, title: String, icon: NSImage, content: Content) {
        self.paneIdentifier = identifier
        self.paneTitle = title
        self.toolbarItemIcon = icon
        super.init(rootView: content)
    }

    @available(*, unavailable)
    @objc dynamic required init?(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - SettingsWindowController

@MainActor
final class SettingsWindowController: NSWindowController {
    private let viewModel: SettingsViewModel
    private var panes: [any SettingsPane] = []
    private var initialTabSelection = true

    init(appModel: AppModel) {
        viewModel = SettingsViewModel(appModel: appModel)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.closable, .titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        super.init(window: window)

        panes = [
            makePane(id: "General", title: "General", icon: "gearshape") {
                GeneralPane(viewModel: self.viewModel)
            },
            makePane(id: "Transcription", title: "Transcription", icon: "waveform") {
                TranscriptionPane(viewModel: self.viewModel)
            },
            makePane(id: "Transcripts", title: "Transcripts", icon: "doc.text") {
                TranscriptsPane(viewModel: self.viewModel)
            },
            makePane(id: "Model", title: "Model", icon: "cpu") {
                ModelPane(viewModel: self.viewModel)
            },
            makePane(id: "Shortcut", title: "Shortcut", icon: "keyboard") {
                ShortcutPane(viewModel: self.viewModel)
            },
            makePane(id: "About", title: "About", icon: "info.circle") {
                AboutPane(viewModel: self.viewModel)
            },
        ]

        configureToolbar()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        guard window?.isVisible != true else {
            openWindow()
            return
        }
        if let item = panes.first {
            window?.toolbar?.selectedItemIdentifier = item.paneIdentifier
            setContentViewForItem(item, animate: !initialTabSelection)
        }
        initialTabSelection = false
        openWindow()
    }

    // MARK: - Private

    private func openWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureToolbar() {
        guard let window else { return }
        let toolbar = NSToolbar(identifier: .init("GloamSettingsToolbar"))
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        toolbar.delegate = self
        window.toolbar = toolbar
        window.toolbarStyle = .preference
    }

    private func setContentViewForItem(_ item: any SettingsPane, animate: Bool = true) {
        guard let window else { return }
        window.title = item.paneTitle
        window.contentView = nil
        let size = item.view.fittingSize
        let contentRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let contentFrame = window.frameRect(forContentRect: contentRect)
        let toolbarHeight = window.frame.size.height - contentFrame.size.height
        let newOrigin = NSPoint(
            x: window.frame.origin.x,
            y: window.frame.origin.y + toolbarHeight
        )
        let newFrame = NSRect(origin: newOrigin, size: contentFrame.size)
        window.setFrame(newFrame, display: true, animate: animate)
        window.contentView = item.view
    }

    private func makePane<V: View>(
        id: String,
        title: String,
        icon: String,
        @ViewBuilder content: () -> V
    ) -> any SettingsPane {
        PaneHostingController(
            identifier: .init(id),
            title: title,
            icon: NSImage(systemSymbolName: icon, accessibilityDescription: title)!,
            content: content()
        )
    }
}

// MARK: - NSToolbarDelegate

extension SettingsWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map { $0.paneIdentifier }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map { $0.paneIdentifier }
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map { $0.paneIdentifier }
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let item = panes.first(where: { $0.paneIdentifier == itemIdentifier }) else {
            return nil
        }
        let toolbarItem = NSToolbarItem(itemIdentifier: item.paneIdentifier)
        toolbarItem.image = item.toolbarItemIcon
        toolbarItem.label = item.paneTitle
        toolbarItem.autovalidates = false
        toolbarItem.target = self
        toolbarItem.action = #selector(changeContentView(_:))
        return toolbarItem
    }

    @objc func changeContentView(_ sender: NSToolbarItem) {
        guard let item = panes.first(where: { $0.paneIdentifier == sender.itemIdentifier }) else {
            return
        }
        setContentViewForItem(item)
    }
}
