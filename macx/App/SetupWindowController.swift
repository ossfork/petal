import AppKit
import SwiftUI

@MainActor
final class SetupWindowController: NSWindowController {
    init(model: AppModel) {
        let rootView = SetupWindowView(model: model)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "MacX Setup"
        window.styleMask = [.titled, .fullSizeContentView]
        window.identifier = NSUserInterfaceItemIdentifier("MacXSetupWindow")
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.animationBehavior = .utilityWindow
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.setContentSize(NSSize(width: 900, height: 560))

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
