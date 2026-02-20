import Shared
import Testing
@testable import GloamModels

@MainActor
@Test
func invalidModelSelectionNormalizesToDefault() {
    let model = OnboardingSetupModel()
    model.selectedModelID = "invalid-model-id"
    #expect(model.selectedModelID == ModelOption.defaultOption.rawValue)
}

@MainActor
@Test
func shortcutStepRequiresConfiguredShortcut() {
    let model = OnboardingSetupModel()
    model.setupStep = .shortcut

    let action = model.onboardingPrimaryButtonTapped(hasConfiguredShortcut: false)

    #expect(action == .none)
    #expect(model.lastError == "Set a push-to-talk shortcut before continuing.")
}

@MainActor
@Test
func downloadStepCompletesWhenDownloadedAndAuthorized() {
    let model = OnboardingSetupModel()
    model.setupStep = .download
    model.microphoneAuthorized = true
    model.accessibilityAuthorized = true
    model.setModelDownloaded(true)

    let action = model.onboardingPrimaryButtonTapped(hasConfiguredShortcut: true)

    #expect(action == .completed)
    #expect(model.hasCompletedSetup)
}
