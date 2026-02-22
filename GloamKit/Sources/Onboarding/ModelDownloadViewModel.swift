import Dependencies
import DownloadClient
import Observation
import Shared

@MainActor
@Observable
public final class ModelDownloadViewModel {
    public var selectedModelID: String = ModelOption.defaultOption.rawValue {
        didSet {
            let normalized = ModelOption.from(modelID: selectedModelID).rawValue
            if selectedModelID != normalized {
                selectedModelID = normalized
                return
            }
            $selectedModelIDStorage.withLock { $0 = normalized }
        }
    }

    public var isDownloadingModel = false
    public var downloadProgress = 0.0
    public var downloadStatus = ""
    public var downloadSpeedText: String?
    public var lastError: String?
    public var transientMessage: String?

    @ObservationIgnored @Dependency(\.downloadClient) private var downloadClient
    @ObservationIgnored @Shared(.selectedModelID) private var selectedModelIDStorage = ModelOption.defaultOption.rawValue

    public init(isPreviewMode: Bool = false) {
        if isPreviewMode {
            selectedModelID = ModelOption.defaultOption.rawValue
            return
        }

        selectedModelID = ModelOption.from(modelID: selectedModelIDStorage).rawValue
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

    public func selectedModelChanged() {
        transientMessage = nil
        lastError = nil

        if isDownloadingModel { return }
        refreshDownloadStateForSelectedModel()
    }

    public func downloadModel() async {
        guard let option = selectedModelOption else {
            lastError = "Select a model to continue."
            return
        }

        guard !isDownloadingModel else { return }

        isDownloadingModel = true
        downloadProgress = 0
        downloadStatus = "Preparing download..."
        downloadSpeedText = nil
        transientMessage = nil
        lastError = nil

        do {
            try await downloadClient.downloadModel(option) { update in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    downloadProgress = min(max(update.fractionCompleted, 0), 1)
                    downloadStatus = update.status
                    downloadSpeedText = update.speedText
                }
            }

            isDownloadingModel = false
            downloadProgress = 1
            downloadSpeedText = nil
            downloadStatus = "Download complete"
            transientMessage = "Model ready. Click Finish Setup to continue."
            lastError = nil
        } catch {
            isDownloadingModel = false
            downloadSpeedText = nil
            lastError = error.localizedDescription
        }
    }

    private func refreshDownloadStateForSelectedModel() {
        if isSelectedModelDownloaded {
            downloadProgress = 1
            downloadStatus = "Model is ready."
            downloadSpeedText = nil
        } else {
            downloadProgress = 0
            downloadStatus = ""
            downloadSpeedText = nil
        }
    }
}
