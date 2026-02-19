import Foundation

enum MacXDeepLinkCommand: String, Sendable {
    case start
    case stop
    case toggle
    case setup

    static func parse(_ url: URL) -> Self? {
        guard url.scheme?.lowercased() == "macx" else { return nil }

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
