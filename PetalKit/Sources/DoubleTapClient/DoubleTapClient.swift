import Dependencies
import DependenciesMacros
import Foundation
import Shared

@DependencyClient
public struct DoubleTapClient: Sendable {
    public var start: @Sendable (_ key: DoubleTapKey, _ interval: TimeInterval, _ onKeyDown: @escaping @Sendable () -> Void, _ onKeyUp: @escaping @Sendable () -> Void) async -> Void = { _, _, _, _ in }
    public var stop: @Sendable () async -> Void = {}
}

extension DoubleTapClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            start: { key, interval, onKeyDown, onKeyUp in
                await MainActor.run {
                    LiveDoubleTapRuntimeContainer.shared.start(
                        key: key,
                        interval: interval,
                        onKeyDown: onKeyDown,
                        onKeyUp: onKeyUp
                    )
                }
            },
            stop: {
                await MainActor.run {
                    LiveDoubleTapRuntimeContainer.shared.stop()
                }
            }
        )
    }
}

extension DoubleTapClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            start: { _, _, _, _ in },
            stop: {}
        )
    }
}

public extension DependencyValues {
    var doubleTapClient: DoubleTapClient {
        get { self[DoubleTapClient.self] }
        set { self[DoubleTapClient.self] = newValue }
    }
}
