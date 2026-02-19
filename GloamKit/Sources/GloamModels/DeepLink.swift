import Foundation

public enum DeepLinkCommand: String, Sendable {
    case start
    case stop
    case toggle
    case setup

    public static func parse(_ url: URL) -> Self? {
        guard url.scheme?.lowercased() == "gloam" else { return nil }

        let hostToken = (url.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let command = Self(rawValue: hostToken) {
            return command
        }

        let pathToken = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if let command = Self(rawValue: pathToken) {
            return command
        }

        return nil
    }
}
