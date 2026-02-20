import AppKit
import Onboarding
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(onboardingModel: OnboardingModel) {
        let rootView = OnboardingView(model: onboardingModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
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

        // Add visual effect view behind SwiftUI content
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        if let contentView = window.contentView {
            contentView.addSubview(visualEffect, positioned: .below, relativeTo: contentView.subviews.first)
            NSLayoutConstraint.activate([
                visualEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                visualEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                visualEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
                visualEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
