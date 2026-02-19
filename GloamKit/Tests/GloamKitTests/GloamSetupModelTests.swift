import GloamShared
import Testing
@testable import GloamModels

@MainActor
@Test
func invalidModelSelectionNormalizesToDefault() {
    let model = GloamSetupModel()
    model.selectedModelID = "invalid-model-id"
    #expect(model.selectedModelID == GloamModelOption.defaultOption.rawValue)
}

@MainActor
@Test
func shortcutStepRequiresConfiguredShortcut() {
    let model = GloamSetupModel()
    model.setupStep = .shortcut

    let action = model.setupPrimaryButtonTapped(hasConfiguredShortcut: false)

    #expect(action == .none)
    #expect(model.lastError == "Set a push-to-talk shortcut before continuing.")
}

@MainActor
@Test
func downloadStepCompletesWhenDownloadedAndAuthorized() {
    let model = GloamSetupModel()
    model.setupStep = .download
    model.microphoneAuthorized = true
    model.setModelDownloaded(true)

    let action = model.setupPrimaryButtonTapped(hasConfiguredShortcut: true)

    #expect(action == .completed)
    #expect(model.hasCompletedSetup)
}
