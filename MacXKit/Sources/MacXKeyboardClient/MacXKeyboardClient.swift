import AppKit
import Dependencies
import DependenciesMacros

public enum MacXKeyPress: Equatable, Sendable {
    case escape
    case character(Character)
    case other
}

@DependencyClient
public struct MacXKeyboardClient: Sendable {
    public var start: @Sendable (@escaping @Sendable (MacXKeyPress) -> Void) async -> Void = { _ in }
    public var stop: @Sendable () async -> Void = {}
}

extension MacXKeyboardClient: DependencyKey {
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

extension MacXKeyboardClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            start: { _ in },
            stop: {}
        )
    }
}

public extension DependencyValues {
    var macXKeyboardClient: MacXKeyboardClient {
        get { self[MacXKeyboardClient.self] }
        set { self[MacXKeyboardClient.self] = newValue }
    }
}

@MainActor
private final class LiveKeyboardRuntime {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var handler: (@Sendable (MacXKeyPress) -> Void)?

    func start(handler: @escaping @Sendable (MacXKeyPress) -> Void) {
        stop()
        self.handler = handler

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
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

    private func handle(_ event: NSEvent) {
        guard let handler else { return }
        handler(Self.keyPress(from: event))
    }

    private static func keyPress(from event: NSEvent) -> MacXKeyPress {
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
