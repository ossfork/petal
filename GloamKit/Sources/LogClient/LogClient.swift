import Dependencies
import DependenciesMacros
import Foundation
import os
import Shared

@DependencyClient
public struct LogClient: Sendable {
    public var debug: @Sendable (_ category: String, _ message: String) -> Void = { _, _ in }
    public var info: @Sendable (_ category: String, _ message: String) -> Void = { _, _ in }
    public var error: @Sendable (_ category: String, _ message: String) -> Void = { _, _ in }
    public var dumpDebug: @Sendable (_ category: String, _ label: String, _ valueDescription: String) -> Void = { _, _, _ in }
}

extension LogClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            debug: { category, message in
                Logger(subsystem: "com.optimalapps.gloam", category: category)
                    .debug("\(message, privacy: .public)")
            },
            info: { category, message in
                Logger(subsystem: "com.optimalapps.gloam", category: category)
                    .info("\(message, privacy: .public)")
            },
            error: { category, message in
                Logger(subsystem: "com.optimalapps.gloam", category: category)
                    .error("\(message, privacy: .public)")
            },
            dumpDebug: { category, label, valueDescription in
                Logger(subsystem: "com.optimalapps.gloam", category: category)
                    .debug("\(label, privacy: .public): \(valueDescription, privacy: .public)")
            }
        )
    }
}

extension LogClient: TestDependencyKey {
    public static var testValue: Self {
        Self()
    }
}

public extension DependencyValues {
    var logClient: LogClient {
        get { self[LogClient.self] }
        set { self[LogClient.self] = newValue }
    }
}

public func appDumpString<T>(_ value: T) -> String {
    String(reflecting: value)
}
