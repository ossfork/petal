import AppKit
import Dependencies
import DependenciesMacros

@DependencyClient
public struct WindowClient: Sendable {
    public var show: @Sendable (_ config: WindowConfig, _ content: @escaping @MainActor @Sendable () -> NSView, _ onClose: @escaping @MainActor @Sendable () -> Void) async -> Void
    public var bringToFront: @Sendable (_ id: String) async -> Void
    public var close: @Sendable (_ id: String) async -> Void
    public var closeAll: @Sendable (_ id: String) async -> Void
    public var isVisible: @Sendable (_ id: String) async -> Bool = { _ in false }
}

extension WindowClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            show: { config, content, onClose in
                await MainActor.run { WindowRuntime.shared.show(config: config, content: content, onClose: onClose) }
            },
            bringToFront: { id in
                await MainActor.run { WindowRuntime.shared.bringToFront(id: id) }
            },
            close: { id in
                await MainActor.run { WindowRuntime.shared.close(id: id) }
            },
            closeAll: { id in
                await MainActor.run { WindowRuntime.shared.closeAll(id: id) }
            },
            isVisible: { id in
                await MainActor.run { WindowRuntime.shared.isVisible(id: id) }
            }
        )
    }
}

extension WindowClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            show: { _, _, _ in },
            bringToFront: { _ in },
            close: { _ in },
            closeAll: { _ in },
            isVisible: { _ in false }
        )
    }
}

public extension DependencyValues {
    var windowClient: WindowClient {
        get { self[WindowClient.self] }
        set { self[WindowClient.self] = newValue }
    }
}
