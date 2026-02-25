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
    public var logFileURL: @Sendable () -> URL? = { nil }
}

extension LogClient: DependencyKey {
    public static var liveValue: Self {
        let fileWriter = LogFileWriter()

        return Self(
            debug: { category, message in
                Logger(subsystem: "com.optimalapps.gloam", category: category)
                    .debug("\(message, privacy: .public)")
                fileWriter.write(level: "DEBUG", category: category, message: message)
            },
            info: { category, message in
                Logger(subsystem: "com.optimalapps.gloam", category: category)
                    .info("\(message, privacy: .public)")
                fileWriter.write(level: "INFO", category: category, message: message)
            },
            error: { category, message in
                Logger(subsystem: "com.optimalapps.gloam", category: category)
                    .error("\(message, privacy: .public)")
                fileWriter.write(level: "ERROR", category: category, message: message)
            },
            dumpDebug: { category, label, valueDescription in
                Logger(subsystem: "com.optimalapps.gloam", category: category)
                    .debug("\(label, privacy: .public): \(valueDescription, privacy: .public)")
                fileWriter.write(level: "DEBUG", category: category, message: "\(label): \(valueDescription)")
            },
            logFileURL: {
                fileWriter.currentFileURL
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

// MARK: - File Writer

private final class LogFileWriter: Sendable {
    private static let logsDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("gloam/logs", isDirectory: true)
    }()

    private let fileHandle: NIOLockedValueBox<FileHandle?>
    let currentFileURL: URL

    init() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.logsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "gloam-\(formatter.string(from: Date())).log"
        let url = Self.logsDirectory.appendingPathComponent(fileName)

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }

        self.currentFileURL = url
        self.fileHandle = NIOLockedValueBox(try? FileHandle(forWritingTo: url))
        fileHandle.withLockedValue { _ = $0?.seekToEndOfFile() }
    }

    func write(level: String, category: String, message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] [\(category)] \(message)\n"

        guard let data = line.data(using: .utf8) else { return }
        fileHandle.withLockedValue { handle in
            handle?.write(data)
        }
    }
}

/// Minimal lock wrapper for Sendable conformance (no NIO dependency needed).
private final class NIOLockedValueBox<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) {
        self._value = value
    }

    func withLockedValue<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}
