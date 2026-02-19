import AppKit

final class KeyboardMonitorService {
    enum KeyPress: Equatable {
        case escape
        case character(Character)
        case other
    }

    typealias Handler = (KeyPress) -> Void

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var handler: Handler?

    func start(handler: @escaping Handler) {
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

    deinit {
        stop()
    }

    private func handle(_ event: NSEvent) {
        guard let handler else { return }
        handler(Self.keyPress(from: event))
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
