import MacXShared
import Testing
@testable import MacXModels

@MainActor
@Test
func invalidModelSelectionNormalizesToDefault() {
    let model = MacXSetupModel()
    model.selectedModelID = "invalid-model-id"
    #expect(model.selectedModelID == MacXModelOption.defaultOption.rawValue)
}

@MainActor
@Test
func shortcutStepRequiresConfiguredShortcut() {
    let model = MacXSetupModel()
    model.setupStep = .shortcut

    let action = model.setupPrimaryButtonTapped(hasConfiguredShortcut: false)

    #expect(action == .none)
    #expect(model.lastError == "Set a push-to-talk shortcut before continuing.")
}

@MainActor
@Test
func downloadStepCompletesWhenDownloadedAndAuthorized() {
    let model = MacXSetupModel()
    model.setupStep = .download
    model.microphoneAuthorized = true
    model.setModelDownloaded(true)

    let action = model.setupPrimaryButtonTapped(hasConfiguredShortcut: true)

    #expect(action == .completed)
    #expect(model.hasCompletedSetup)
}
