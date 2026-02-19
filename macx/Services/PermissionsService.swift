import ApplicationServices
import AppKit
import AVFoundation
import Foundation

enum MicrophonePermissionState: Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
final class PermissionsService {
    func microphonePermissionState() -> MicrophonePermissionState {
        let captureState = microphonePermissionStateFromCaptureDevice()

        if #available(macOS 14.0, *) {
            let audioApplicationState: MicrophonePermissionState
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                audioApplicationState = .authorized
            case .undetermined:
                audioApplicationState = .notDetermined
            case .denied:
                audioApplicationState = .denied
            @unknown default:
                audioApplicationState = .denied
            }

            if captureState == .authorized || audioApplicationState == .authorized {
                return .authorized
            }

            if captureState == .notDetermined || audioApplicationState == .notDetermined {
                return .notDetermined
            }

            return .denied
        }

        return captureState
    }

    func requestMicrophonePermission() async -> Bool {
        if microphonePermissionState() == .authorized {
            return true
        }

        if #available(macOS 14.0, *) {
            let appPermissionGranted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }

            if appPermissionGranted {
                return true
            }
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            return true
        }

        let capturePermissionGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { isGranted in
                continuation.resume(returning: isGranted)
            }
        }

        if capturePermissionGranted {
            return true
        }

        return microphonePermissionState() == .authorized
    }

    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func promptForAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openMicrophonePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openAccessibilityPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func microphonePermissionStateFromCaptureDevice() -> MicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .restricted, .denied:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            return .denied
        }
    }
}
