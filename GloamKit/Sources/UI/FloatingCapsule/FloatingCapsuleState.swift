import Observation

@MainActor
@Observable
public final class FloatingCapsuleState {
    public enum Phase: Equatable {
        case hidden
        case recording
        case confirmCancel
        case trimming
        case speeding
        case transcribing
        case refining
        case error(String)
    }

    public var phase: Phase = .hidden
    public var level: Double = 0
    public var transcriptionProgress: Double = 0

    public init() {}
}
