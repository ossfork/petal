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
            let audioApplicationState = microphonePermissionStateFromAudioApplication()

            if captureState == .authorized, audioApplicationState == .authorized {
                return .authorized
            }

            if captureState == .denied || audioApplicationState == .denied {
                return .denied
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

        var appPermissionGranted = true
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                appPermissionGranted = true
            case .undetermined:
                appPermissionGranted = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { isGranted in
                        continuation.resume(returning: isGranted)
                    }
                }
            case .denied:
                appPermissionGranted = false
            @unknown default:
                appPermissionGranted = false
            }
        }

        let capturePermissionGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            capturePermissionGranted = true
        case .notDetermined:
            capturePermissionGranted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
        case .restricted, .denied:
            capturePermissionGranted = false
        @unknown default:
            capturePermissionGranted = false
        }

        if #available(macOS 14.0, *) {
            return appPermissionGranted && capturePermissionGranted && microphonePermissionState() == .authorized
        }

        return capturePermissionGranted && microphonePermissionState() == .authorized
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

    @available(macOS 14.0, *)
    private func microphonePermissionStateFromAudioApplication() -> MicrophonePermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .authorized
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
