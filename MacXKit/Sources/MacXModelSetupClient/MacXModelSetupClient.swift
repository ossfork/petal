import Dependencies
import DependenciesMacros
import Foundation
import MacXMLXClient
import MacXShared

public struct MacXModelDownloadUpdate: Sendable, Equatable {
    public var fractionCompleted: Double
    public var status: String
    public var speedText: String?

    public init(fractionCompleted: Double, status: String, speedText: String?) {
        self.fractionCompleted = fractionCompleted
        self.status = status
        self.speedText = speedText
    }
}

@DependencyClient
public struct MacXModelSetupClient: Sendable {
    public var isModelDownloaded: @Sendable (MacXModelOption) -> Bool = { _ in false }
    public var downloadModel: @Sendable (MacXModelOption, @escaping @Sendable (MacXModelDownloadUpdate) -> Void) async throws -> Void
}

extension MacXModelSetupClient: DependencyKey {
    public static var liveValue: Self {
        Self(
            isModelDownloaded: { option in
                @Dependency(\.macXMLXClient) var mlxClient
                return mlxClient.isModelDownloaded(option.mlxModelInfo)
            },
            downloadModel: { option, progress in
                @Dependency(\.macXMLXClient) var mlxClient
                try await mlxClient.downloadModel(option.mlxModelInfo, { fractionCompleted, status in
                    progress(
                        MacXModelDownloadUpdate(
                            fractionCompleted: fractionCompleted,
                            status: status,
                            speedText: speedText(from: status)
                        )
                    )
                })
            }
        )
    }
}

extension MacXModelSetupClient: TestDependencyKey {
    public static var testValue: Self {
        Self(
            isModelDownloaded: { _ in false },
            downloadModel: { _, _ in }
        )
    }
}

public extension DependencyValues {
    var macXModelSetupClient: MacXModelSetupClient {
        get { self[MacXModelSetupClient.self] }
        set { self[MacXModelSetupClient.self] = newValue }
    }
}

private func speedText(from status: String) -> String? {
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

private extension MacXModelOption {
    var mlxModelInfo: MacXMLXModelInfo {
        let descriptor = descriptor
        return MacXMLXModelInfo(
            id: descriptor.id,
            repoId: descriptor.repoID,
            name: descriptor.name,
            summary: descriptor.summary,
            size: descriptor.size,
            quantization: descriptor.quantization,
            parameters: descriptor.parameters,
            recommended: descriptor.recommended
        )
    }
}
