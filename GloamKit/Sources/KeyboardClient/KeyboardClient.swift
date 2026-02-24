import AppKit
import Dependencies
import DependenciesMacros

public enum KeyPress: Equatable, Sendable {
    case escape
    case character(Character)
    case other
}

/// Return `true` from the handler to swallow the event (prevent it from reaching text fields).
public typealias KeyPressHandler = @Sendable (KeyPress) -> Bool

@DependencyClient
public struct KeyboardClient: Sendable {
    public var start: @Sendable (@escaping KeyPressHandler) async -> Void = { _ in }
    public var stop: @Sendable () async -> Void = {}
}

extension KeyboardClient: DependencyKey {
    public static var liveValue: Self {
        return Self(
            start: { handler in
                await MainActor.run { LiveKeyboardRuntimeContainer.shared.start(handler: handler) }
            },
            stop: {
                await MainActor.run { LiveKeyboardRuntimeContainer.shared.stop() }
            }
        )
    }
}

extension KeyboardClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            start: { _ in },
            stop: { }
        )
    }
}

public extension DependencyValues {
    var keyboardClient: KeyboardClient {
        get { self[KeyboardClient.self] }
        set { self[KeyboardClient.self] = newValue }
    }
}

@MainActor
private final class LiveKeyboardRuntime {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var handler: KeyPressHandler?

    func start(handler: @escaping KeyPressHandler) {
        stop()
        self.handler = handler

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = self?.handle(event) ?? false
            return consumed ? nil : event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(event)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        handler = nil
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard let handler else { return false }
        return handler(Self.keyPress(from: event))
    }

    private static func keyPress(from event: NSEvent) -> KeyPress {
        if event.keyCode == 53 {
            return .escape
        }

        guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else {
            return .other
        }

        let normalized = characters.lowercased()
        guard let character = normalized.first else {
            return .other
        }

        return .character(character)
    }
}

@MainActor
private enum LiveKeyboardRuntimeContainer {
    static let shared = LiveKeyboardRuntime()
}
