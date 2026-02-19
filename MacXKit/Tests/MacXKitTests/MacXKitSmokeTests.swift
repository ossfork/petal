import Testing
@testable import MacXShared
@testable import MacXModels
@testable import MacXUI
@testable import MacXAudioClient
@testable import MacXPermissionsClient
@testable import MacXPasteClient
@testable import MacXKeyboardClient
@testable import MacXFloatingCapsuleClient
@testable import MacXModelSetupClient
@testable import MacXTranscriptionClient

@Test
func modulesCompile() {
    _ = MacXShared.self
    _ = MacXModels.self
    _ = MacXUI.self
    _ = MacXAudioClient.self
    _ = MacXPermissionsClient.self
    _ = MacXPasteClient.self
    _ = MacXKeyboardClient.self
    _ = MacXFloatingCapsuleClient.self
    _ = MacXModelSetupClient.self
    _ = MacXTranscriptionClient.self
    _ = MacXModelOption.defaultOption
    _ = MacXTranscriptionMode.verbatim
}
