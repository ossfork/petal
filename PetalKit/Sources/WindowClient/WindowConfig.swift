import AppKit

public struct WindowConfig: Sendable {
    public var id: String
    public var title: String
    public var style: WindowStyle
    public var size: CGSize
    public var animationBehavior: NSWindow.AnimationBehavior
    public var tabbingMode: NSWindow.TabbingMode
    public var isReleasedWhenClosed: Bool
    public var collectionBehavior: NSWindow.CollectionBehavior

    public init(
        id: String,
        title: String,
        style: WindowStyle,
        size: CGSize,
        animationBehavior: NSWindow.AnimationBehavior = .default,
        tabbingMode: NSWindow.TabbingMode = .disallowed,
        isReleasedWhenClosed: Bool = false,
        collectionBehavior: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    ) {
        self.id = id
        self.title = title
        self.style = style
        self.size = size
        self.animationBehavior = animationBehavior
        self.tabbingMode = tabbingMode
        self.isReleasedWhenClosed = isReleasedWhenClosed
        self.collectionBehavior = collectionBehavior
    }
}
