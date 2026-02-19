import Observation

@MainActor
@Observable
public final class KitAppModel {
    public let setupModel: SetupModel
    public let recordingModel: RecordingSessionModel

    public init(
        setupModel: SetupModel = SetupModel(),
        recordingModel: RecordingSessionModel = RecordingSessionModel()
    ) {
        self.setupModel = setupModel
        self.recordingModel = recordingModel
    }
}
