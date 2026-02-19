public enum MacXTranscriptionMode: String, CaseIterable, Identifiable, Sendable {
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
            return "Exact transcription of what was said"
        case .smart:
            return "Process with a custom instruction"
        }
    }
}
