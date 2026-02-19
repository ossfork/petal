import Dependencies
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
        NSApplication.shared.setActivationPolicy(.accessory)
        prepareDependencies { _ in }
        logger.info("macx app initialized")
        print("[macx] app initialized")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model, updatesModel: updatesModel)
                .onAppear {
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController.startUpdater()
    }
}
