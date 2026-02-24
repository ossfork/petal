import Dependencies
import DownloadClient
import Foundation
import Observation
import Shared

public enum ModelDownloadPhase: Sendable, Equatable {
    case idle
    case preparing
    case downloading
    case paused
    case completed
    case failed(String)
}

@MainActor
@Observable
public final class ModelDownloadModel {
    @ObservationIgnored @Shared(.selectedModelID) public var selectedModelID = ModelOption.defaultOption.rawValue

    public var phase: ModelDownloadPhase = .idle
    public var downloadProgress = 0.0
    public var downloadStatus = ""
    public var downloadSpeedText: String?
    public var lastError: String?
    public var transientMessage: String?

    public var isDownloadingModel: Bool {
        get { Self.isDownloading(phase) }
        set {
            guard newValue != Self.isDownloading(phase) else { return }
            if newValue {
                phase = .downloading
            } else {
                phase = downloadProgress >= 1 ? .completed : .idle
            }
        }
    }

    public var isPaused: Bool {
        get {
            guard case .paused = phase else { return false }
            return true
        }
        set {
            if newValue {
                phase = .paused
            } else if case .paused = phase {
                phase = downloadProgress >= 1 ? .completed : .idle
            }
        }
    }

    @ObservationIgnored @Dependency(\.downloadClient) private var downloadClient

    public init(isPreviewMode: Bool = false) {
        if isPreviewMode {
            selectedModelID = ModelOption.defaultOption.rawValue
            return
        }

        selectedModelID = ModelOption.from(modelID: selectedModelID).rawValue
        refreshDownloadStateForSelectedModel()
    }

    public var selectedModelOption: ModelOption? {
        ModelOption(rawValue: selectedModelID)
    }

    public var isSelectedModelDownloaded: Bool {
        guard let selectedModelOption else { return false }
        return downloadClient.isModelDownloaded(selectedModelOption)
    }

    public var downloadSummaryText: String {
        let percent = Int((downloadProgress * 100).rounded())

        if let downloadSpeedText {
            return "\(percent)% - \(downloadSpeedText)"
        }

        return "\(percent)%"
    }

    public var modelDirectoryURL: URL? {
        guard let option = selectedModelOption else { return nil }
        return downloadClient.modelDirectoryURL(option)
    }

    public func downloadButtonTapped() async {
        await startDownload(resetProgress: true)
    }

    public func pauseButtonTapped() {
        guard isDownloadingModel else { return }
        downloadClient.pauseDownload()
        phase = .paused
        downloadStatus = "Download paused"
        downloadSpeedText = nil
    }

    public func resumeButtonTapped() async {
        guard isPaused else { return }
        await startDownload(resetProgress: false)
    }

    public func cancelButtonTapped() {
        downloadClient.cancelDownload()
        resetToIdle()
    }

    public func selectedModelChanged() {
        transientMessage = nil
        lastError = nil

        if isDownloadingModel || isPaused { return }
        refreshDownloadStateForSelectedModel()
    }

    public func downloadModel() async {
        await downloadButtonTapped()
    }

    public func pauseDownload() {
        pauseButtonTapped()
    }

    public func resumeDownload() async {
        await resumeButtonTapped()
    }

    public func cancelDownload() {
        cancelButtonTapped()
    }

    private func startDownload(resetProgress: Bool) async {
        guard let option = selectedModelOption else {
            let message = "Select a model to continue."
            phase = .failed(message)
            lastError = message
            return
        }

        guard !isDownloadingModel else { return }

        phase = .preparing
        if resetProgress {
            downloadProgress = 0
        }
        downloadStatus = "Preparing download..."
        downloadSpeedText = nil
        transientMessage = nil
        lastError = nil

        do {
            try await downloadClient.downloadModel(option) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    applyProgressUpdate(update)
                }
            }

            phase = .completed
            downloadProgress = 1
            downloadSpeedText = nil
            downloadStatus = "Download complete"
            transientMessage = "Model ready. Click Finish Setup to continue."
            lastError = nil
        } catch is CancellationError {
        } catch let error as DownloadClientFailure {
            handleDownloadFailure(error)
        } catch {
            handleDownloadFailure(.failed(error.localizedDescription))
        }
    }

    private func applyProgressUpdate(_ update: DownloadProgress) {
        if case .paused = phase { return }

        if phase == .preparing || phase == .idle {
            phase = .downloading
        }

        downloadProgress = min(max(update.fractionCompleted, 0), 1)
        downloadStatus = update.status
        downloadSpeedText = update.speedText
    }

    private func handleDownloadFailure(_ failure: DownloadClientFailure) {
        switch failure {
        case .paused:
            phase = .paused
            downloadStatus = "Download paused"
            downloadSpeedText = nil
            lastError = nil
        case .cancelled:
            resetToIdle()
        case .aria2BinaryMissing, .failed:
            let message = failure.errorDescription ?? "Download failed."
            phase = .failed(message)
            downloadSpeedText = nil
            lastError = message
        }
    }

    private func refreshDownloadStateForSelectedModel() {
        if isSelectedModelDownloaded {
            phase = .completed
            downloadProgress = 1
            downloadStatus = "Model is ready."
            downloadSpeedText = nil
        } else {
            phase = .idle
            downloadProgress = 0
            downloadStatus = ""
            downloadSpeedText = nil
        }
    }

    private func resetToIdle() {
        phase = .idle
        downloadProgress = 0
        downloadStatus = ""
        downloadSpeedText = nil
        lastError = nil
    }

    private static func isDownloading(_ phase: ModelDownloadPhase) -> Bool {
        switch phase {
        case .preparing, .downloading:
            return true
        case .idle, .paused, .completed, .failed:
            return false
        }
    }
}
