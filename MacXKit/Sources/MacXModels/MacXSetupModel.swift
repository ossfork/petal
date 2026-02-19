import MacXPermissionsClient
import MacXShared
import Observation
import Sharing

@MainActor
@Observable
public final class MacXSetupModel {
    public enum SetupStep: Int, CaseIterable, Sendable {
        case model
        case shortcut
        case download
    }

    @ObservationIgnored @Shared(.hasCompletedSetup) private var hasCompletedSetupStorage = false
    @ObservationIgnored @Shared(.selectedModelID) private var selectedModelIDStorage = MacXModelOption.defaultOption.rawValue
    @ObservationIgnored @Shared(.transcriptionMode) private var transcriptionModeStorage = MacXTranscriptionMode.verbatim.rawValue
    @ObservationIgnored @Shared(.smartPrompt) private var smartPromptStorage = "Clean up filler words and repeated phrases. Return a polished version of what was said."

    public var hasCompletedSetup = false {
        didSet {
            $hasCompletedSetupStorage.withLock { $0 = hasCompletedSetup }
        }
    }

    public var selectedModelID = MacXModelOption.defaultOption.rawValue {
        didSet {
            let normalized = MacXModelOption.from(modelID: selectedModelID).rawValue
            if selectedModelID != normalized {
                selectedModelID = normalized
                return
            }
            $selectedModelIDStorage.withLock { $0 = normalized }
        }
    }

    public var transcriptionMode: MacXTranscriptionMode = .verbatim {
        didSet {
            $transcriptionModeStorage.withLock { $0 = transcriptionMode.rawValue }
        }
    }

    public var smartPrompt = "Clean up filler words and repeated phrases. Return a polished version of what was said." {
        didSet {
            $smartPromptStorage.withLock { $0 = smartPrompt }
        }
    }

    public var setupStep: SetupStep = .model
    public var isDownloadingModel = false
    public var downloadProgress = 0.0
    public var downloadStatus = ""
    public var downloadSpeedText: String?
    public var lastError: String?
    public var transientMessage: String?
    public var microphonePermissionState: MicrophonePermissionState = .notDetermined
    public var microphoneAuthorized = false
    public var accessibilityAuthorized = false
    public var isSelectedModelDownloaded = false

    public init() {
        hasCompletedSetup = hasCompletedSetupStorage
        selectedModelID = MacXModelOption.from(modelID: selectedModelIDStorage).rawValue
        transcriptionMode = MacXTranscriptionMode(rawValue: transcriptionModeStorage) ?? .verbatim
        smartPrompt = smartPromptStorage
        beginSetupFlow()
    }

    public var selectedModelOption: MacXModelOption? {
        MacXModelOption(rawValue: selectedModelID)
    }

    public var setupStepItems: [SetupStep] {
        SetupStep.allCases
    }

    public var setupPrimaryButtonTitle: String {
        switch setupStep {
        case .model, .shortcut:
            return "Continue"
        case .download:
            if isDownloadingModel {
                return "Downloading..."
            }

            if !microphoneAuthorized {
                switch microphonePermissionState {
                case .authorized:
                    break
                case .notDetermined:
                    return "Grant Microphone"
                case .denied:
                    return "Open Mic Settings"
                }
            }

            if isSelectedModelDownloaded {
                return "Finish Setup"
            }

            return "Download Model"
        }
    }

    public var setupPrimaryButtonDisabled: Bool {
        isDownloadingModel
    }

    public var setupCanGoBack: Bool {
        setupStep != .model && !isDownloadingModel
    }

    public var setupStepTitle: String {
        switch setupStep {
        case .model:
            return "Choose Model"
        case .shortcut:
            return "Choose Shortcut"
        case .download:
            return "Download & Permissions"
        }
    }

    public var setupStepDescription: String {
        switch setupStep {
        case .model:
            return "Pick a Voxtral Mini model. You can change this later from the menu bar."
        case .shortcut:
            return "Set a shortcut. Quick tap toggles recording; holding for at least 2 seconds uses press-to-talk."
        case .download:
            return "Allow permissions and download your selected model."
        }
    }

    public var setupDownloadSummaryText: String {
        let percent = Int((downloadProgress * 100).rounded())

        if let downloadSpeedText {
            return "\(percent)% - \(downloadSpeedText)"
        }

        return "\(percent)%"
    }

    public func setupStepDisplayName(_ step: SetupStep) -> String {
        switch step {
        case .model:
            return "Model"
        case .shortcut:
            return "Shortcut"
        case .download:
            return "Download"
        }
    }

    public func selectedModelSelectionChanged() {
        transientMessage = nil
        lastError = nil
    }

    public func setModelDownloaded(_ downloaded: Bool) {
        isSelectedModelDownloaded = downloaded
    }

    public func beginSetupFlow() {
        setupStep = .model
        downloadSpeedText = nil
        downloadProgress = isSelectedModelDownloaded ? 1 : 0
        downloadStatus = isSelectedModelDownloaded ? "Model already downloaded." : ""
    }

    public func setupBackButtonTapped() {
        guard setupCanGoBack else { return }

        switch setupStep {
        case .model:
            break
        case .shortcut:
            setupStep = .model
        case .download:
            setupStep = .shortcut
        }

        lastError = nil
    }

    public func setupPrimaryButtonTapped(hasConfiguredShortcut: Bool) -> SetupPrimaryAction {
        switch setupStep {
        case .model:
            guard selectedModelOption != nil else {
                lastError = "Please select a valid model."
                return .none
            }

            setupStep = .shortcut
            lastError = nil
            return .advanced
        case .shortcut:
            guard hasConfiguredShortcut else {
                lastError = "Set a push-to-talk shortcut before continuing."
                return .none
            }

            setupStep = .download
            lastError = nil
            return .requestPermissions
        case .download:
            if !microphoneAuthorized {
                return .requestMicrophone
            }

            if isSelectedModelDownloaded {
                completeSetup()
                return .completed
            }

            return .downloadModel
        }
    }

    public func completeSetup() {
        hasCompletedSetup = true
        transientMessage = "MacX is ready. Quick tap to toggle listening, or hold for push-to-talk."
    }
}

public enum SetupPrimaryAction: Sendable, Equatable {
    case none
    case advanced
    case requestPermissions
    case requestMicrophone
    case downloadModel
    case completed
}
