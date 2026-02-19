enum TranscriptionMode: String, CaseIterable, Identifiable, Sendable {
    case verbatim
    case smart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .verbatim: "Verbatim"
        case .smart: "Smart"
        }
    }

    var description: String {
        switch self {
        case .verbatim: "Exact transcription of what was said"
        case .smart: "Process with a custom instruction"
        }
    }
}
