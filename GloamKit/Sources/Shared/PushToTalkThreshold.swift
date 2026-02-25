public enum PushToTalkThreshold: String, CaseIterable, Identifiable, Sendable, Codable {
    case short = "short"
    case medium = "medium"
    case long = "long"

    public var id: String { rawValue }

    public var seconds: Double {
        switch self {
        case .short: 0.4
        case .medium: 1.0
        case .long: 2.0
        }
    }

    public var displayName: String {
        switch self {
        case .short: "0.4s"
        case .medium: "1.0s"
        case .long: "2.0s"
        }
    }
}
