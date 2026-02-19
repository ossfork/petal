import Dependencies
import Foundation
import os

#if canImport(CustomDump)
import CustomDump
#endif

struct AppLogClient: Sendable {
    var debug: @Sendable (_ category: String, _ message: String) -> Void
    var info: @Sendable (_ category: String, _ message: String) -> Void
    var error: @Sendable (_ category: String, _ message: String) -> Void
    var dumpDebug: @Sendable (_ category: String, _ label: String, _ valueDescription: String) -> Void
}

private enum AppLogClientKey: DependencyKey {
    static var liveValue: AppLogClient {
        AppLogClient(
            debug: { category, message in
                Logger(subsystem: "com.optimalapps.macx", category: category)
                    .debug("\(message, privacy: .public)")
            },
            info: { category, message in
                Logger(subsystem: "com.optimalapps.macx", category: category)
                    .info("\(message, privacy: .public)")
            },
            error: { category, message in
                Logger(subsystem: "com.optimalapps.macx", category: category)
                    .error("\(message, privacy: .public)")
            },
            dumpDebug: { category, label, valueDescription in
                Logger(subsystem: "com.optimalapps.macx", category: category)
                    .debug("\(label, privacy: .public): \(valueDescription, privacy: .public)")
            }
        )
    }

    static var testValue: AppLogClient {
        AppLogClient(
            debug: { _, _ in },
            info: { _, _ in },
            error: { _, _ in },
            dumpDebug: { _, _, _ in }
        )
    }
}

extension DependencyValues {
    var appLogClient: AppLogClient {
        get { self[AppLogClientKey.self] }
        set { self[AppLogClientKey.self] = newValue }
    }
}

func appDumpString<T>(_ value: T) -> String {
    #if canImport(CustomDump)
    String(customDumping: value)
    #else
    String(reflecting: value)
    #endif
}
