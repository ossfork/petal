import AppKit
import Sauce
import Foundation
import IssueReporting
import os

enum PasteResult: Equatable, Sendable {
    case pasted
    case copiedOnly

    var rawValue: String {
        switch self {
        case .pasted:
            return "pasted"
        case .copiedOnly:
            return "copied_only"
        }
    }
}

@MainActor
final class PasteService {
    private typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]
    private let logger = Logger(subsystem: "com.optimalapps.macx", category: "PasteService")

    func paste(text: String) async -> PasteResult {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            reportIssue("Could not place transcript on pasteboard.")
            logger.error("Failed to write transcript to pasteboard")
            restorePasteboard(pasteboard, snapshot: snapshot)
            return .copiedOnly
        }

        guard postCommandV() else {
            logger.info("Paste automation unavailable; restoring clipboard snapshot")
            restorePasteboard(pasteboard, snapshot: snapshot)
            return .copiedOnly
        }

        try? await Task.sleep(for: .milliseconds(180))
        restorePasteboard(pasteboard, snapshot: snapshot)
        logger.info("Transcript pasted and clipboard restored")

        return .pasted
    }

    private func postCommandV() -> Bool {
        guard AXIsProcessTrusted() else {
            logger.info("Accessibility permission missing; cannot auto-paste")
            return false
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            reportIssue("Could not create CGEventSource for paste event.")
            return false
        }

        let commandKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = Sauce.shared.keyCode(for: .v)

        guard
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false)
        else {
            reportIssue("Could not create CGEvents for paste event.")
            return false
        }

        commandDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)

        return true
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            return entry
        }
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()

        guard !snapshot.isEmpty else {
            return
        }

        let items = snapshot.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(items)
    }
}
