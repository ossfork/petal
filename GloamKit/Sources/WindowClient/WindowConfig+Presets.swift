import AppKit

extension WindowConfig {
    public static let about = WindowConfig(
        id: "GloamAboutWindow",
        title: "About Gloam",
        style: .chromeless(.init(
            hidesCloseButton: false,
            hidesMiniaturizeButton: true,
            hidesZoomButton: true,
            isFloating: true
        )),
        size: CGSize(width: 280, height: 500)
    )

    public static let onboarding = WindowConfig(
        id: "GloamOnboardingWindow",
        title: "Gloam Onboarding",
        style: .chromeless(.init(
            hidesCloseButton: true,
            hidesMiniaturizeButton: true,
            hidesZoomButton: true,
            isFloating: true,
            visualEffect: VisualEffectConfig(material: .hudWindow, blendingMode: .behindWindow)
        )),
        size: CGSize(width: 820, height: 512),
        animationBehavior: .utilityWindow
    )
}
