import AppKit
import Onboarding
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(onboardingModel: OnboardingModel) {
        let rootView = OnboardingView(model: onboardingModel)
        let hostingController = NSHostingController(rootView: rootView)
        let containerController = NSViewController()
        let containerView = NSView()

        containerController.view = containerView

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(visualEffect)
        containerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: containerView.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        containerController.addChild(hostingController)

        let window = NSWindow(contentViewController: containerController)
        window.title = "Gloam Onboarding"
        window.styleMask = [.titled, .fullSizeContentView]
        window.identifier = NSUserInterfaceItemIdentifier("GloamOnboardingWindow")
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
        window.setContentSize(NSSize(width: 820, height: 512))

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
