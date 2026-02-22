public enum TranscriptionMode: String, CaseIterable, Identifiable, Sendable {
    case verbatim
    case smart

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .verbatim:
            return "Verbatim"
        case .smart:
            return "Smart"
        }
    }

    public var description: String {
        switch self {
        case .verbatim:
            return "Word-for-word transcription"
        case .smart:
            return "Refine transcription with a custom prompt"
        }
    }
}
