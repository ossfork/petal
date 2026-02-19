import AppKit
import SwiftUI

@MainActor
final class SetupWindowController: NSWindowController {
    init(model: AppModel) {
        let rootView = SetupWindowView(model: model)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "MacX Setup"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 560, height: 500))

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
