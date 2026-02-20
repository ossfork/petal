import Dependencies
import Darwin
import os
import Sparkle
import SwiftUI

@main
struct GloamApp: App {
    @State private var model: AppModel
    @State private var menuBarViewModel: MenuBarContentViewModel
    @State private var updatesModel: CheckForUpdatesModel?
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let logger = Logger(subsystem: "com.optimalapps.gloam", category: "App")

    init() {
        let appModel = AppModel()
        _model = State(initialValue: appModel)
        _menuBarViewModel = State(initialValue: MenuBarContentViewModel(appModel: appModel))

        guard SingleInstanceLock.shared.acquire() else {
            Logger(subsystem: "com.optimalapps.gloam", category: "App")
                .error("Another gloam instance is already running. exiting duplicate process.")
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        prepareDependencies { _ in }
        logger.info("gloam app initialized")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: menuBarViewModel)
        } label: {
            Label("Gloam", systemImage: model.menuBarSymbolName)
                .onAppear {
                    appDelegate.model = model
                    if updatesModel == nil {
                        updatesModel = CheckForUpdatesModel(updater: appDelegate.updaterController.updater)
                        menuBarViewModel.setUpdatesModel(updatesModel)
                    }
                }
        }
        .menuBarExtraStyle(.window)

    }
}

private final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private var fileDescriptor: Int32 = -1
    private let lockPath = "\(NSTemporaryDirectory())com.optimalapps.gloam.lock"

    private init() {}

    func acquire() -> Bool {
        if fileDescriptor != -1 {
            return true
        }

        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor != -1 else { return false }

        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return false
        }

        fileDescriptor = descriptor
        return true
    }

    deinit {
        guard fileDescriptor != -1 else { return }
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    weak var model: AppModel?
    private let logger = Logger(subsystem: "com.optimalapps.gloam", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
        updaterController.startUpdater()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model else { return }

        for url in urls {
            guard let command = GloamDeepLinkCommand.parse(url) else { continue }
            Task { @MainActor in
                await model.handleDeepLink(command)
            }
        }
    }

    private func enforceSingleInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard running.count > 1 else { return }

        logger.error("Detected multiple running instances. terminating pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        NSApp.terminate(nil)
    }
}
