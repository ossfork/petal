import Foundation
import VoxtralCore

@MainActor
final class ModelSetupService {
    struct DownloadUpdate: Sendable {
        var fractionCompleted: Double
        var status: String
        var speedText: String?
    }

    typealias DownloadProgress = @Sendable (DownloadUpdate) -> Void

    func isModelDownloaded(_ option: ModelOption) -> Bool {
        ModelDownloader.findModelPath(for: option.modelInfo) != nil
    }

    func downloadModel(_ option: ModelOption, progress: DownloadProgress? = nil) async throws {
        _ = try await ModelDownloader.download(option.modelInfo, progress: { fractionCompleted, status in
            progress?(
                DownloadUpdate(
                    fractionCompleted: fractionCompleted,
                    status: status,
                    speedText: Self.speedText(from: status)
                )
            )
        })
    }

    private nonisolated static func speedText(from status: String) -> String? {
        guard let openingParen = status.lastIndex(of: "("), let closingParen = status.lastIndex(of: ")") else {
            return nil
        }

        guard openingParen < closingParen else {
            return nil
        }

        let candidate = status[status.index(after: openingParen)..<closingParen]
        let speed = String(candidate)
        return speed.hasSuffix("/s") ? speed : nil
    }
}
