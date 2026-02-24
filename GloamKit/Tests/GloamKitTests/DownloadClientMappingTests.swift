import Dependencies
import Foundation
import Shared
import Testing
@testable import DownloadClient
@testable import MLXClient

@Test
func downloadClientNormalizesProgressAndExtractsSpeedText() async throws {
    var updates: [DownloadProgress] = []

    try await withDependencies {
        $0.mlxClient.downloadModel = { _, progress in
            progress(1.4, "Downloading model files... 52% (18.2 MB/s)")
            progress(-0.3, "Downloading model files... 0%")
        }
    } operation: {
        try await DownloadClient.liveValue.downloadModel(.defaultOption) { update in
            updates.append(update)
        }
    }

    #expect(updates.count == 2)
    #expect(updates[0].fractionCompleted == 1)
    #expect(updates[0].speedText == "18.2 MB/s")
    #expect(updates[1].fractionCompleted == 0)
    #expect(updates[1].speedText == nil)
}

@Test
func downloadClientMapsMLXDownloadErrorsToTypedFailures() async {
    await assertMappedFailure(from: .paused, expected: .paused)
    await assertMappedFailure(from: .cancelled, expected: .cancelled)
    await assertMappedFailure(from: .aria2BinaryMissing, expected: .aria2BinaryMissing)
    await assertMappedFailure(from: .failed("network down"), expected: .failed("network down"))
}

@Test
func downloadClientMapsUnexpectedErrorsToFailedCase() async {
    struct FixtureError: LocalizedError {
        var errorDescription: String? { "fixture failure" }
    }

    do {
        try await withDependencies {
            $0.mlxClient.downloadModel = { _, _ in
                throw FixtureError()
            }
        } operation: {
            try await DownloadClient.liveValue.downloadModel(.defaultOption) { _ in }
        }
        Issue.record("Expected a failure but download succeeded.")
    } catch let error as DownloadClientFailure {
        switch error {
        case let .failed(message):
            #expect(message == "fixture failure")
        default:
            Issue.record("Expected .failed for unknown errors, got \(error.localizedDescription).")
        }
    } catch {
        Issue.record("Expected DownloadClientFailure, got \(error.localizedDescription).")
    }
}

private func assertMappedFailure(from source: MLXDownloadError, expected: DownloadClientFailure) async {
    do {
        try await withDependencies {
            $0.mlxClient.downloadModel = { _, _ in
                throw source
            }
        } operation: {
            try await DownloadClient.liveValue.downloadModel(.defaultOption) { _ in }
        }
        Issue.record("Expected \(expected.localizedDescription), but download succeeded.")
    } catch let error as DownloadClientFailure {
        #expect(error == expected)
    } catch {
        Issue.record("Expected DownloadClientFailure, got \(error.localizedDescription).")
    }
}
