import Dependencies
import Darwin
import os
import Carbon.HIToolbox
import Sparkle
import SwiftUI
import WindowClient

@main
struct PetalApp: App {
    @State private var model: AppModel
    @State private var menuBarViewModel: MenuBarContentViewModel
    @State private var updatesModel: CheckForUpdatesModel?
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let logger = Logger(subsystem: "com.optimalapps.petal", category: "App")

    init() {
        let appModel = AppModel()
        _model = State(initialValue: appModel)
        _menuBarViewModel = State(initialValue: MenuBarContentViewModel(appModel: appModel))
        AppDelegate.bootstrapModel = appModel

        guard SingleInstanceLock.shared.acquire() else {
            Logger(subsystem: "com.optimalapps.petal", category: "App")
                .error("Another petal instance is already running. exiting duplicate process.")
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        prepareDependencies { _ in }
        logger.info("petal app initialized")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: menuBarViewModel)
        } label: {
            Label("Petal", systemImage: model.menuBarSymbolName)
                .onAppear {
                    appDelegate.model = model
                    if updatesModel == nil {
                        updatesModel = CheckForUpdatesModel(updater: appDelegate.updaterController.updater)
                        menuBarViewModel.setUpdatesModel(updatesModel)
                        appDelegate.updatesModel = updatesModel
                    }
                }
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Petal") {
                    NSApp.sendAction(#selector(AppDelegate.showAboutPanel), to: nil, from: nil)
                }
            }
        }


    }
}

private final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private var fileDescriptor: Int32 = -1
    private let lockPath = "\(NSTemporaryDirectory())com.optimalapps.petal.lock"

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
    static var bootstrapModel: AppModel?

    let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    weak var model: AppModel? {
        didSet { flushPendingDeepLinksIfNeeded() }
    }
    var updatesModel: CheckForUpdatesModel?
    @Dependency(\.windowClient) private var windowClient
    private let logger = Logger(subsystem: "com.optimalapps.petal", category: "AppDelegate")
    private var pendingDeepLinkCommands: [PetalDeepLinkCommand] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if model == nil, let bootstrapModel = Self.bootstrapModel {
            model = bootstrapModel
        }
        registerDeepLinkAppleEventHandler()
        logger.info("Registered deep link AppleEvent handler")
        enforceSingleInstance()
        updaterController.startUpdater()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        logger.info("Received application(open:) URLs count=\(urls.count, privacy: .public)")
        for url in urls {
            guard let command = PetalDeepLinkCommand.parse(url) else { continue }
            logger.info("Parsed deep link from application(open:): \(command.rawValue, privacy: .public)")
            handleOrQueueDeepLink(command)
        }
    }

    @objc
    func showAboutPanel() {
        NSApp.setActivationPolicy(.regular)
        let updatesModel = self.updatesModel
        Task {
            await windowClient.show(.about, {
                NSHostingView(rootView: AboutView(updatesModel: updatesModel))
            }, {
                NSApp.setActivationPolicy(.accessory)
            })
        }
    }

    private func enforceSingleInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard running.count > 1 else { return }

        logger.error("Detected multiple running instances. terminating pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        NSApp.terminate(nil)
    }

    private func registerDeepLinkAppleEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc
    private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              let command = PetalDeepLinkCommand.parse(url)
        else { return }
        logger.info("Parsed deep link from kAEGetURL: \(command.rawValue, privacy: .public)")
        handleOrQueueDeepLink(command)
    }

    private func handleOrQueueDeepLink(_ command: PetalDeepLinkCommand) {
        if command == .checkForUpdates {
            triggerUpdateCheckFromDeepLink()
            return
        }

        guard let model else {
            pendingDeepLinkCommands.append(command)
            logger.debug("Queued deep link command because model is not ready: \(command.rawValue, privacy: .public)")
            return
        }
        Task { @MainActor in
            await model.handleDeepLink(command)
        }
    }

    private func flushPendingDeepLinksIfNeeded() {
        guard let model, !pendingDeepLinkCommands.isEmpty else { return }
        let queued = pendingDeepLinkCommands
        pendingDeepLinkCommands.removeAll()
        for command in queued {
            Task { @MainActor in
                await model.handleDeepLink(command)
            }
        }
    }

    private func triggerUpdateCheckFromDeepLink() {
        let updater = updaterController.updater
        guard updater.canCheckForUpdates else {
            logger.debug("Ignored check-for-updates deep link because updater is not ready yet")
            return
        }

        logger.info("Triggering Sparkle update check from deep link")
        updater.checkForUpdates()
    }
}
