import AppKit
import Observation
import Sparkle

@Observable
@MainActor
final class CheckForUpdatesModel {
    var canCheckForUpdates = false

    private let updater: SPUUpdater
    private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        self.updater = updater
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
