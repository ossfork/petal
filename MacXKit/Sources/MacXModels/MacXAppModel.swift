import Observation

@MainActor
@Observable
public final class MacXAppModel {
    public let setupModel: MacXSetupModel
    public let recordingModel: MacXRecordingSessionModel

    public init(
        setupModel: MacXSetupModel = MacXSetupModel(),
        recordingModel: MacXRecordingSessionModel = MacXRecordingSessionModel()
    ) {
        self.setupModel = setupModel
        self.recordingModel = recordingModel
    }
}
