import Dependencies
import DependenciesTestSupport
import Foundation
import Shared
import Testing
@testable import DownloadClient
@testable import ModelDownloadFeature

@Test
func modelCompletesDownloadAndTransitionsToCompletedPhase() async throws {
    try await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
        $0.downloadClient.downloadModel = { _, progress in
            progress(0.4, "Downloading model files... 40% (12.0 MB/s)")
            progress(0.9, "Downloading model files... 90% (11.0 MB/s)")
        }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)
        await model.downloadButtonTapped()

        #expect(model.phase == .completed)
        #expect(model.downloadProgress == 1)
        #expect(model.downloadStatus == "Download complete")
        #expect(model.downloadSpeedText == nil)
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
            progress(0.75, "Downloading model files... 75% (9.0 MB/s)")
        }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)

        await model.downloadButtonTapped()
        #expect(model.phase == .paused)
        #expect(model.downloadStatus == "Download paused")

        await model.resumeButtonTapped()
        #expect(model.phase == .completed)
        #expect(model.downloadProgress == 1)
        #expect(await attempts.current() == 2)
    }
}

@Test
func modelPauseAndCancelButtonsMutateStateDeterministically() async throws {
    try await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)
        model.isDownloadingModel = true
        model.downloadProgress = 0.58
        model.downloadStatus = "Downloading model files..."

        model.pauseButtonTapped()
        #expect(model.phase == .paused)
        #expect(model.downloadStatus == "Download paused")

        model.cancelButtonTapped()
        #expect(model.phase == .idle)
        #expect(model.downloadProgress == 0)
        #expect(model.downloadStatus.isEmpty)
        #expect(model.downloadSpeedText == nil)
    }
}

@Test
func modelTransitionsToFailedPhaseForTypedFailures() async throws {
    try await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in false }
        $0.downloadClient.downloadModel = { _, _ in
            throw DownloadClientFailure.failed("network failure")
        }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)
        await model.downloadButtonTapped()

        #expect(model.phase == .failed("network failure"))
        #expect(model.lastError == "network failure")
        #expect(model.isDownloadingModel == false)
    }
}

@Test
func selectedModelChangedRefreshesDownloadedState() async throws {
    try await withDependencies {
        $0.downloadClient.isModelDownloaded = { _ in true }
    } operation: {
        let model = ModelDownloadModel(isPreviewMode: true)
        model.selectedModelChanged()

        #expect(model.phase == .completed)
        #expect(model.downloadProgress == 1)
        #expect(model.downloadStatus == "Model is ready.")
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
