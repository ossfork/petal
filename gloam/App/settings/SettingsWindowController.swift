import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let viewModel: SettingsViewModel

    init(appModel: AppModel) {
        viewModel = SettingsViewModel(appModel: appModel)

        let rootView = SettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Gloam Settings"
        window.identifier = NSUserInterfaceItemIdentifier("GloamSettingsWindow")
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 960, height: 680))
        window.minSize = NSSize(width: 900, height: 600)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        viewModel.selectedSection = .general
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
