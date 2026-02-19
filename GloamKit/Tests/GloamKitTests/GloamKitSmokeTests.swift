import Testing
@testable import GloamShared
@testable import GloamModels
@testable import GloamUI
@testable import GloamAudioClient
@testable import GloamPermissionsClient
@testable import GloamPasteClient
@testable import GloamKeyboardClient
@testable import GloamFloatingCapsuleClient
@testable import GloamAudioTrimClient
@testable import GloamAudioSpeedClient
@testable import GloamModelSetupClient
@testable import GloamTranscriptionClient

@Test
func modulesCompile() {
    _ = GloamShared.self
    _ = GloamModels.self
    _ = GloamUI.self
    _ = GloamAudioClient.self
    _ = GloamPermissionsClient.self
    _ = GloamPasteClient.self
    _ = GloamKeyboardClient.self
    _ = GloamFloatingCapsuleClient.self
    _ = GloamAudioTrimClient.self
    _ = GloamAudioSpeedClient.self
    _ = GloamModelSetupClient.self
    _ = GloamTranscriptionClient.self
    _ = GloamModelOption.defaultOption
    _ = GloamTranscriptionMode.verbatim
}
