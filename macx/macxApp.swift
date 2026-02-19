import Dependencies
import Darwin
import os
import Sparkle
import SwiftUI

@main
struct macxApp: App {
    @State private var model = AppModel()
    @State private var updatesModel: CheckForUpdatesModel?
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let logger = Logger(subsystem: "com.optimalapps.macx", category: "App")

    init() {
        guard SingleInstanceLock.shared.acquire() else {
            Logger(subsystem: "com.optimalapps.macx", category: "App")
                .error("Another macx instance is already running. exiting duplicate process.")
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        prepareDependencies { _ in }
        logger.info("macx app initialized")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model, updatesModel: updatesModel)
                .onAppear {
                    appDelegate.model = model
                    if updatesModel == nil {
                        updatesModel = CheckForUpdatesModel(updater: appDelegate.updaterController.updater)
                    }
                }
        } label: {
            Label("MacX", systemImage: model.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SetupWindowView(model: model)
        }
    }
}

private final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private var fileDescriptor: Int32 = -1
    private let lockPath = "\(NSTemporaryDirectory())com.optimalapps.macx.lock"

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
    private let logger = Logger(subsystem: "com.optimalapps.macx", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
        updaterController.startUpdater()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model else { return }

        for url in urls {
            guard let command = MacXDeepLinkCommand.parse(url) else { continue }
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
