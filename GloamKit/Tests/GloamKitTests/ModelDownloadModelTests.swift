import Dependencies
import DependenciesTestSupport
import Foundation
import Shared
import Testing
@testable import DownloadClient
@testable import ModelDownloadFeature

@Test
func modelCompletesDownloadAndTransitionsToDownloadedState() async throws {
    try await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
        $0.downloadClient.downloadModel = { _, progress in
            progress(DownloadProgress(fractionCompleted: 0.4, status: "Downloading model files... 40%", speedText: "12.0 MB/s"))
            progress(DownloadProgress(fractionCompleted: 0.9, status: "Downloading model files... 90%", speedText: "11.0 MB/s"))
        }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)
        await model.downloadButtonTapped()

        #expect(model.state == .downloaded)
        #expect(model.lastError == nil)
    }
}

@Test
func modelHandlesPauseAndResumeAcrossRetries() async throws {
    let attempts = AttemptCounter()

    try await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
        $0.downloadClient.downloadModel = { _, progress in
            let attempt = await attempts.next()
            if attempt == 1 {
                throw DownloadClientFailure.paused
            }
            progress(DownloadProgress(fractionCompleted: 0.75, status: "Downloading model files... 75%", speedText: "9.0 MB/s"))
        }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)

        await model.downloadButtonTapped()
        #expect(model.state.isPaused)

        await model.resumeButtonTapped()
        #expect(model.state == .downloaded)
        #expect(await attempts.current() == 2)
    }
}

@Test
func modelPauseAndCancelButtonsMutateStateDeterministically() async throws {
    try await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)
        model.state = .downloading(.init(fraction: 0.58, statusText: "Downloading model files..."))

        model.pauseButtonTapped()
        #expect(model.state.isPaused)

        model.cancelButtonTapped()
        #expect(model.state == .notDownloaded)
    }
}

@Test
func modelTransitionsToFailedStateForTypedFailures() async throws {
    try await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
        $0.downloadClient.downloadModel = { _, _ in
            throw DownloadClientFailure.failed("network failure")
        }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)
        await model.downloadButtonTapped()

        #expect(model.state == .failed("network failure"))
        #expect(model.lastError == "network failure")
        #expect(model.state.isActive == false)
    }
}

@Test
func selectedModelChangedRefreshesDownloadedState() async throws {
    try await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in true }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)
        model.selectedModelChanged()

        #expect(model.state == .downloaded)
    }
}

private actor AttemptCounter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }

    func current() -> Int {
        value
    }
}
