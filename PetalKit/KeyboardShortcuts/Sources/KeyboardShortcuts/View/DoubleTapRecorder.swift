#if os(macOS)

import AppKit
import Carbon.HIToolbox
import SwiftUI

public struct DoubleTapRecorder: View {
    @Binding var key: DoubleTapKey
    @Namespace private var namespace

    @State private var mode: Mode = .ready
    @State private var symbolName = "xmark.circle.fill"
    @State private var delayedResetTask: Task<Void, Never>?

    public enum DoubleTapKey: Codable, Hashable, Sendable {
        case unconfigured
        case configured(keyCode: Int, isModifier: Bool, displayName: String)

        public var isConfigured: Bool {
            if case .configured = self { return true }
            return false
        }

        public var displayName: String? {
            if case let .configured(_, _, name) = self { return name }
            return nil
        }

        public var keyCode: Int? {
            if case let .configured(code, _, _) = self { return code }
            return nil
        }

        public var isModifier: Bool? {
            if case let .configured(_, isMod, _) = self { return isMod }
            return nil
        }
    }

    private enum Mode: Equatable {
        case ready
        case recording
        case set(String)

        var isRecording: Bool {
            if case .recording = self { return true }
            return false
        }

        var isSet: Bool {
            if case .set = self { return true }
            return false
        }

        var thereIsNoKeys: Bool {
            switch self {
            case .ready, .recording: return true
            case .set: return false
            }
        }
    }

    public init(key: Binding<DoubleTapKey>) {
        self._key = key
    }

    public var body: some View {
        ZStack {
            _DoubleTapRecorderView(
                isActive: mode.isRecording,
                onKeyRecorded: { keyCode, isModifier, displayName in
                    key = .configured(keyCode: keyCode, isModifier: isModifier, displayName: displayName)
                    withAnimation(.spring(duration: 0.4)) {
                        mode = .set(displayName)
                        symbolName = "checkmark.circle.fill"
                    }
                    delayedResetTask = Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.default) {
                            symbolName = "xmark.circle.fill"
                        }
                    }
                },
                onCancelled: {
                    withAnimation(.spring(duration: 0.4)) {
                        mode = key.isConfigured ? .set(key.displayName!) : .ready
                    }
                }
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)

            HStack {
                Button(action: activateRecorder) {
                    ZStack {
                        switch mode {
                        case .ready:
                            Text("RECORD")
                                .commandStyle()
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)
                                ))
                        case .recording:
                            HStack {
                                BlinkingLight()
                                Text("PRESS ANY KEY")
                                    .commandStyle()
                                    .foregroundStyle(Color.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 8)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))

                        case let .set(displayName):
                            HStack(spacing: 2) {
                                ShortcutSymbol(symbol: displayName)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                            .transition(.offset(x: -30).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, mode.thereIsNoKeys ? 8 : 2)
                    .frame(height: 26)
                    .visualEffect(.adaptive(.windowBackground))
                    .clipShape(RoundedRectangle(cornerRadius: mode.thereIsNoKeys ? 13 : 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: mode.thereIsNoKeys ? 13 : 6, style: .continuous).stroke(.secondary, lineWidth: 0.5).opacity(0.3))
                    .contentShape(RoundedRectangle(cornerRadius: mode.thereIsNoKeys ? 13 : 6, style: .continuous))
                }
                .buttonStyle(.plain)

                if mode != .ready {
                    Button(
                        action: {
                            if mode.isRecording {
                                withAnimation(.spring(duration: 0.4)) {
                                    mode = key.isConfigured ? .set(key.displayName!) : .ready
                                }
                            } else if mode.isSet {
                                key = .unconfigured
                                withAnimation(.spring(duration: 0.4)) {
                                    mode = .ready
                                }
                            }
                        },
                        label: {
                            Image(systemName: symbolName)
                                .fontWeight(.bold)
                                .imageScale(.large)
                                .foregroundColor(Color.secondary)
                        }
                    )
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity).combined(with: .offset(x: -30)))
                }
            }
        }
        .animation(.spring(duration: 0.4), value: mode)
        .onAppear {
            if let name = key.displayName {
                mode = .set(name)
            }
        }
    }

    private func activateRecorder() {
        guard !mode.isRecording else { return }
        delayedResetTask?.cancel()
        symbolName = "xmark.circle.fill"
        withAnimation(.spring(duration: 0.4)) {
            mode = .recording
        }
    }
}

// MARK: - NSViewRepresentable for key capture

private struct _DoubleTapRecorderView: NSViewRepresentable {
    let isActive: Bool
    let onKeyRecorded: (Int, Bool, String) -> Void
    let onCancelled: () -> Void

    func makeNSView(context: Context) -> _DoubleTapNSView {
        let view = _DoubleTapNSView()
        view.onKeyRecorded = onKeyRecorded
        view.onCancelled = onCancelled
        return view
    }

    func updateNSView(_ nsView: _DoubleTapNSView, context: Context) {
        nsView.onKeyRecorded = onKeyRecorded
        nsView.onCancelled = onCancelled
        if isActive {
            nsView.startRecording()
        } else {
            nsView.stopRecording()
        }
    }
}

final class _DoubleTapNSView: NSView {
    var onKeyRecorded: ((Int, Bool, String) -> Void)?
    var onCancelled: (() -> Void)?
    private var isRecording = false
    private var pendingModifierKeyCode: Int?
    private var localMonitor: Any?
    private var flagsMonitor: Any?

    override var canBecomeKeyView: Bool { isRecording }
    override var acceptsFirstResponder: Bool { isRecording }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        pendingModifierKeyCode = nil
        KeyboardShortcuts.isPaused = true
        window?.makeFirstResponder(self)
        installMonitors()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        pendingModifierKeyCode = nil
        KeyboardShortcuts.isPaused = false
        removeMonitors()
    }

    private func installMonitors() {
        removeMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }

            if event.type == .flagsChanged {
                self.handleFlagsChanged(event)
                return nil
            }

            // keyDown
            self.handleKeyDown(event)
            return nil
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        pendingModifierKeyCode = nil
        let keyCode = Int(event.keyCode)

        // Reject Tab (focus navigation)
        if event.keyCode == UInt16(kVK_Tab) {
            stopRecording()
            onCancelled?()
            return
        }

        // Escape cancels recording
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            onCancelled?()
            return
        }

        // Delete/Backspace clears the key
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            stopRecording()
            onCancelled?()
            return
        }

        let displayName = regularKeyDisplayName(keyCode: keyCode, event: event)
        stopRecording()
        onKeyRecorded?(keyCode, false, displayName)
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let isModifierKey = Self.modifierKeyCodes.contains(keyCode)
        guard isModifierKey else { return }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) != [] {
            // Modifier pressed down
            pendingModifierKeyCode = keyCode
        } else if let pending = pendingModifierKeyCode, pending == keyCode {
            // Modifier released — this is the key
            pendingModifierKeyCode = nil
            let displayName = Self.modifierDisplayName(for: keyCode)
            stopRecording()
            onKeyRecorded?(keyCode, true, displayName)
        }
    }

    private func regularKeyDisplayName(keyCode: Int, event: NSEvent) -> String {
        // Try to get the character from the event
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand,
        kVK_Shift, kVK_RightShift,
        kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl,
        kVK_Function,
    ]

    private static func modifierDisplayName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Command, kVK_RightCommand: return "\u{2318}"
        case kVK_Shift, kVK_RightShift:     return "\u{21E7}"
        case kVK_Option, kVK_RightOption:    return "\u{2325}"
        case kVK_Control, kVK_RightControl:  return "\u{2303}"
        case kVK_Function:                   return "fn"
        default:                             return "Mod"
        }
    }

    deinit {
        removeMonitors()
    }
}

#if DEBUG
#Preview {
    DoubleTapRecorder(key: .constant(.unconfigured))
        .padding(50)
}
#endif

#endif
