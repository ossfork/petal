import Observation

@MainActor
@Observable
public final class KitAppModel {
    public let onboardingSetupModel: OnboardingSetupModel
    public let recordingModel: RecordingSessionModel

    public init(
        onboardingSetupModel: OnboardingSetupModel = OnboardingSetupModel(),
        recordingModel: RecordingSessionModel = RecordingSessionModel()
    ) {
        self.onboardingSetupModel = onboardingSetupModel
        self.recordingModel = recordingModel
    }
}
