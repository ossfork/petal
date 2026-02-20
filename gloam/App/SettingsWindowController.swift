import AppKit
import KeyboardShortcuts
import Sparkle
import Shared

@MainActor
final class SettingsWindowController: NSWindowController {
    private let rootController: SettingsRootViewController

    init(appModel: AppModel) {
        rootController = SettingsRootViewController(appModel: appModel)

        let window = NSWindow(contentViewController: rootController)
        window.title = "Gloam Settings"
        window.identifier = NSUserInterfaceItemIdentifier("GloamSettingsWindow")
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.setContentSize(NSSize(width: 940, height: 640))
        window.minSize = NSSize(width: 900, height: 600)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        rootController.select(section: .general)
        rootController.refreshVisiblePane()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum SettingsPalette {
    static let panelLine = NSColor.white.withAlphaComponent(0.10)
    static let rowLine = NSColor.white.withAlphaComponent(0.08)
    static let textPrimary = NSColor(calibratedWhite: 0.88, alpha: 1)
    static let textSecondary = NSColor(calibratedWhite: 0.70, alpha: 1)
    static let selectedFill = NSColor.white.withAlphaComponent(0.12)
    static let cardFill = NSColor.white.withAlphaComponent(0.05)
    static let cardBorder = NSColor.white.withAlphaComponent(0.11)
}

private enum SettingsSectionID: CaseIterable {
    case general
    case model
    case shortcut
    case transcription
    case permissions
    case history
    case about

    var title: String {
        switch self {
        case .general:
            return "General"
        case .model:
            return "Model"
        case .shortcut:
            return "Shortcut"
        case .transcription:
            return "Transcription"
        case .permissions:
            return "Permissions"
        case .history:
            return "History"
        case .about:
            return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape.fill"
        case .model:
            return "cpu.fill"
        case .shortcut:
            return "keyboard.fill"
        case .transcription:
            return "waveform"
        case .permissions:
            return "lock.shield.fill"
        case .history:
            return "clock.arrow.circlepath"
        case .about:
            return "info.circle.fill"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .general:
            return NSColor(calibratedRed: 0.58, green: 0.60, blue: 0.63, alpha: 1)
        case .model:
            return NSColor(calibratedRed: 0.94, green: 0.62, blue: 0.35, alpha: 1)
        case .shortcut:
            return NSColor(calibratedRed: 0.56, green: 0.83, blue: 0.66, alpha: 1)
        case .transcription:
            return NSColor(calibratedRed: 0.75, green: 0.53, blue: 0.94, alpha: 1)
        case .permissions:
            return NSColor(calibratedRed: 0.94, green: 0.47, blue: 0.55, alpha: 1)
        case .history:
            return NSColor(calibratedRed: 0.43, green: 0.82, blue: 0.80, alpha: 1)
        case .about:
            return NSColor(calibratedRed: 0.53, green: 0.70, blue: 0.95, alpha: 1)
        }
    }
}

private struct SidebarGroup {
    let title: String?
    let items: [SettingsSectionID]
}

private let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(
        title: nil,
        items: [
            .general,
            .model,
            .shortcut,
            .transcription
        ]
    ),
    SidebarGroup(
        title: "Privacy & Data",
        items: [
            .permissions,
            .history
        ]
    ),
    SidebarGroup(
        title: "Gloam",
        items: [
            .about
        ]
    )
]

@MainActor
private final class SettingsRootViewController: NSViewController {
    private let appModel: AppModel
    private let sidebarWidth: CGFloat = 248

    private var selectedSection: SettingsSectionID = .general
    private var sidebarItems: [SettingsSectionID: SettingsSidebarItemControl] = [:]
    private var paneViews: [SettingsSectionID: SettingsPaneView] = [:]

    private let headerIconBubble = NSView()
    private let headerIconView = NSImageView()
    private let headerTitleLabel = NSTextField(labelWithString: "")
    private let paneContainer = NSView()

    private var refreshTimer: Timer?

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        refreshTimer?.invalidate()
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        let surface = SettingsSurfaceView()
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)

        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            surface.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.distribution = .fill
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: surface.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 0
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let leftTop = NSView()
        leftTop.translatesAutoresizingMaskIntoConstraints = false
        let trafficLights = makeTrafficLightsView()
        leftTop.addSubview(trafficLights)

        NSLayoutConstraint.activate([
            trafficLights.leadingAnchor.constraint(equalTo: leftTop.leadingAnchor, constant: 16),
            trafficLights.centerYAnchor.constraint(equalTo: leftTop.centerYAnchor)
        ])

        let topVerticalLine = makeLine()
        topVerticalLine.widthAnchor.constraint(equalToConstant: 1).isActive = true

        let rightTop = NSView()
        rightTop.translatesAutoresizingMaskIntoConstraints = false
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 9
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        rightTop.addSubview(headerStack)

        headerIconBubble.wantsLayer = true
        headerIconBubble.layer?.cornerRadius = 7
        headerIconBubble.translatesAutoresizingMaskIntoConstraints = false
        headerIconBubble.addSubview(headerIconView)

        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        headerIconView.contentTintColor = .white

        headerTitleLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        headerTitleLabel.textColor = SettingsPalette.textPrimary
        headerTitleLabel.lineBreakMode = .byTruncatingTail

        headerStack.addArrangedSubview(headerIconBubble)
        headerStack.addArrangedSubview(headerTitleLabel)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: rightTop.leadingAnchor, constant: 14),
            headerStack.centerYAnchor.constraint(equalTo: rightTop.centerYAnchor),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: rightTop.trailingAnchor, constant: -14),

            headerIconBubble.widthAnchor.constraint(equalToConstant: 22),
            headerIconBubble.heightAnchor.constraint(equalToConstant: 22),

            headerIconView.centerXAnchor.constraint(equalTo: headerIconBubble.centerXAnchor),
            headerIconView.centerYAnchor.constraint(equalTo: headerIconBubble.centerYAnchor)
        ])

        topRow.addArrangedSubview(leftTop)
        topRow.addArrangedSubview(topVerticalLine)
        topRow.addArrangedSubview(rightTop)

        leftTop.widthAnchor.constraint(equalToConstant: sidebarWidth).isActive = true
        topRow.heightAnchor.constraint(equalToConstant: 50).isActive = true

        let topHorizontalLine = makeLine()
        topHorizontalLine.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let bodyRow = NSStackView()
        bodyRow.orientation = .horizontal
        bodyRow.alignment = .top
        bodyRow.spacing = 0
        bodyRow.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = makeSidebarView()
        let bodyVerticalLine = makeLine()
        bodyVerticalLine.widthAnchor.constraint(equalToConstant: 1).isActive = true

        let mainPanel = NSView()
        mainPanel.translatesAutoresizingMaskIntoConstraints = false
        mainPanel.addSubview(paneContainer)
        paneContainer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            paneContainer.leadingAnchor.constraint(equalTo: mainPanel.leadingAnchor, constant: 14),
            paneContainer.trailingAnchor.constraint(equalTo: mainPanel.trailingAnchor, constant: -22),
            paneContainer.topAnchor.constraint(equalTo: mainPanel.topAnchor, constant: 12),
            paneContainer.bottomAnchor.constraint(equalTo: mainPanel.bottomAnchor, constant: -14)
        ])

        bodyRow.addArrangedSubview(sidebar)
        bodyRow.addArrangedSubview(bodyVerticalLine)
        bodyRow.addArrangedSubview(mainPanel)
        sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth).isActive = true

        rootStack.addArrangedSubview(topRow)
        rootStack.addArrangedSubview(topHorizontalLine)
        rootStack.addArrangedSubview(bodyRow)

        select(section: .general)
        startRefreshTimer()
    }

    func select(section: SettingsSectionID) {
        selectedSection = section

        for (id, item) in sidebarItems {
            item.isSelectedItem = id == section
        }

        headerTitleLabel.stringValue = section.title
        headerIconBubble.layer?.backgroundColor = section.tintColor.cgColor
        headerIconView.image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title)

        showPane(for: section)
    }

    func refreshVisiblePane() {
        paneViews[selectedSection]?.refresh()
    }

    private func showPane(for section: SettingsSectionID) {
        let pane = paneViews[section] ?? buildPane(for: section)
        paneViews[section] = pane

        paneContainer.subviews.forEach { $0.removeFromSuperview() }
        paneContainer.addSubview(pane)
        pane.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
            pane.topAnchor.constraint(equalTo: paneContainer.topAnchor),
            pane.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor)
        ])

        pane.refresh()
    }

    private func buildPane(for section: SettingsSectionID) -> SettingsPaneView {
        let pane: SettingsPaneView
        switch section {
        case .general:
            pane = GeneralSettingsPaneView(appModel: appModel)
        case .model:
            pane = ModelSettingsPaneView(appModel: appModel)
        case .shortcut:
            pane = ShortcutSettingsPaneView(appModel: appModel)
        case .transcription:
            pane = TranscriptionSettingsPaneView(appModel: appModel)
        case .permissions:
            pane = PermissionsSettingsPaneView(appModel: appModel)
        case .history:
            pane = HistorySettingsPaneView(appModel: appModel)
        case .about:
            pane = AboutSettingsPaneView(appModel: appModel)
        }

        pane.onNeedsRefresh = { [weak self] in
            self?.refreshVisiblePane()
        }

        return pane
    }

    private func makeSidebarView() -> NSView {
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor, constant: -12)
        ])

        for (groupIndex, group) in sidebarGroups.enumerated() {
            if let title = group.title {
                let heading = makeHeadingLabel(title)
                stack.addArrangedSubview(heading)
            }

            for item in group.items {
                let sidebarItem = SettingsSidebarItemControl(section: item)
                sidebarItem.target = self
                sidebarItem.action = #selector(sidebarItemTapped(_:))
                stack.addArrangedSubview(sidebarItem)
                sidebarItems[item] = sidebarItem
            }

            if groupIndex < sidebarGroups.count - 1 {
                stack.addArrangedSubview(makeSidebarSpacingView(height: 6))
            }
        }

        return sidebar
    }

    private func makeTrafficLightsView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeTrafficDot(color: NSColor(calibratedRed: 0.95, green: 0.37, blue: 0.34, alpha: 1)))
        stack.addArrangedSubview(makeTrafficDot(color: NSColor(calibratedWhite: 0.51, alpha: 1)))
        stack.addArrangedSubview(makeTrafficDot(color: NSColor(calibratedWhite: 0.51, alpha: 1)))

        return stack
    }

    private func makeTrafficDot(color: NSColor) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 6
        dot.layer?.backgroundColor = color.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12)
        ])
        return dot
    }

    private func makeLine() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = SettingsPalette.panelLine.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        return line
    }

    private func makeHeadingLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        label.textColor = SettingsPalette.textSecondary
        return label
    }

    private func makeSidebarSpacingView(height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    @objc
    private func sidebarItemTapped(_ sender: SettingsSidebarItemControl) {
        select(section: sender.section)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshVisiblePane()
            }
        }

        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }
}

@MainActor
private class SettingsPaneView: NSView {
    let appModel: AppModel
    var onNeedsRefresh: (() -> Void)?

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func refresh() {}

    func makeCardView() -> SettingsCardView {
        SettingsCardView()
    }

    func makeKeyValueRow(title: String, trailing: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = SettingsPalette.textPrimary

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, spacer, trailing])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    func makeDescriptionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = SettingsPalette.textSecondary
        return label
    }

    func makeRowLine() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = SettingsPalette.rowLine.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    func makePrimaryButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    func makeSecondaryValueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = SettingsPalette.textSecondary
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

@MainActor
private final class GeneralSettingsPaneView: SettingsPaneView {
    private let statusValueLabel = NSTextField(labelWithString: "")
    private let modelValueLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    override init(appModel: AppModel) {
        super.init(appModel: appModel)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        let card = makeCardView()
        stack.addArrangedSubview(card)

        statusValueLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        statusValueLabel.textColor = SettingsPalette.textPrimary

        modelValueLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        modelValueLabel.textColor = SettingsPalette.textSecondary
        modelValueLabel.lineBreakMode = .byTruncatingTail

        let setupButton = makePrimaryButton("Open Onboarding", action: #selector(openSetupAssistant))
        let historyButton = makePrimaryButton("Open History Folder", action: #selector(openHistoryFolder))

        card.stack.addArrangedSubview(makeKeyValueRow(title: "Status", trailing: statusValueLabel))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(makeKeyValueRow(title: "Current Model", trailing: modelValueLabel))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(makeKeyValueRow(title: "Model Download", trailing: setupButton))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(makeKeyValueRow(title: "Stored Transcripts", trailing: historyButton))

        messageLabel.font = NSFont.systemFont(ofSize: 12)
        messageLabel.textColor = SettingsPalette.textSecondary
        messageLabel.maximumNumberOfLines = 3
        stack.addArrangedSubview(messageLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func refresh() {
        statusValueLabel.stringValue = appModel.statusTitle
        modelValueLabel.stringValue = appModel.currentModelSummary
        messageLabel.stringValue = appModel.transientMessage ?? appModel.lastError ?? ""
        messageLabel.isHidden = messageLabel.stringValue.isEmpty
    }

    @objc
    private func openSetupAssistant() {
        appModel.changeModelButtonTapped()
        onNeedsRefresh?()
    }

    @objc
    private func openHistoryFolder() {
        appModel.openHistoryFolderButtonTapped()
        onNeedsRefresh?()
    }
}

@MainActor
private final class ModelSettingsPaneView: SettingsPaneView {
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let downloadedLabel = NSTextField(labelWithString: "")

    override init(appModel: AppModel) {
        super.init(appModel: appModel)

        for option in ModelOption.allCases {
            modelPopup.addItem(withTitle: option.displayName)
            modelPopup.lastItem?.representedObject = option.rawValue
        }
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        let card = makeCardView()
        stack.addArrangedSubview(card)

        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.textColor = SettingsPalette.textSecondary
        summaryLabel.maximumNumberOfLines = 3

        sizeLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        sizeLabel.textColor = SettingsPalette.textSecondary

        downloadedLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let setupButton = makePrimaryButton("Download or Switch in Onboarding", action: #selector(openSetupAssistant))

        card.stack.addArrangedSubview(makeKeyValueRow(title: "Selected Model", trailing: modelPopup))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(summaryLabel)
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(makeKeyValueRow(title: "Model Size", trailing: sizeLabel))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(makeKeyValueRow(title: "Download Status", trailing: downloadedLabel))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(makeKeyValueRow(title: "Onboarding", trailing: setupButton))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func refresh() {
        selectCurrentModel()
        guard let option = appModel.selectedModelOption else { return }

        summaryLabel.stringValue = option.summary
        sizeLabel.stringValue = option.sizeLabel
        downloadedLabel.stringValue = appModel.isSelectedModelDownloaded ? "Downloaded" : "Not Downloaded"
        downloadedLabel.textColor = appModel.isSelectedModelDownloaded
            ? NSColor.systemGreen
            : NSColor.systemOrange
    }

    private func selectCurrentModel() {
        let rawValue = appModel.selectedModelID
        for item in modelPopup.itemArray where (item.representedObject as? String) == rawValue {
            modelPopup.select(item)
            break
        }
    }

    @objc
    private func modelChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String else { return }
        appModel.selectedModelID = rawValue
        onNeedsRefresh?()
    }

    @objc
    private func openSetupAssistant() {
        appModel.changeModelButtonTapped()
        onNeedsRefresh?()
    }
}

@MainActor
private final class ShortcutSettingsPaneView: SettingsPaneView {
    private let recorder = KeyboardShortcuts.RecorderCocoa(for: .pushToTalk)
    private let shortcutValueLabel = NSTextField(labelWithString: "")
    private let usageLabel = NSTextField(wrappingLabelWithString: "")

    override init(appModel: AppModel) {
        super.init(appModel: appModel)

        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        let card = makeCardView()
        stack.addArrangedSubview(card)

        shortcutValueLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        shortcutValueLabel.textColor = SettingsPalette.textPrimary

        usageLabel.font = NSFont.systemFont(ofSize: 12)
        usageLabel.textColor = SettingsPalette.textSecondary
        usageLabel.maximumNumberOfLines = 3

        card.stack.addArrangedSubview(makeKeyValueRow(title: "Push-to-talk Shortcut", trailing: recorder))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(makeKeyValueRow(title: "Current", trailing: shortcutValueLabel))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(usageLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func refresh() {
        shortcutValueLabel.stringValue = appModel.shortcutDisplayText
        usageLabel.stringValue = appModel.shortcutUsageText
    }
}

@MainActor
private final class TranscriptionSettingsPaneView: SettingsPaneView, NSTextViewDelegate {
    private let modeControl = NSSegmentedControl(labels: TranscriptionMode.allCases.map(\.displayName), trackingMode: .selectOne, target: nil, action: nil)
    private let modeDescriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let promptContainer = NSView()
    private let promptTextView = NSTextView()

    override init(appModel: AppModel) {
        super.init(appModel: appModel)

        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.segmentStyle = .rounded
        modeControl.selectedSegment = 0

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let card = makeCardView()
        stack.addArrangedSubview(card)

        modeDescriptionLabel.font = NSFont.systemFont(ofSize: 12)
        modeDescriptionLabel.textColor = SettingsPalette.textSecondary
        modeDescriptionLabel.maximumNumberOfLines = 3

        let promptLabel = NSTextField(labelWithString: "Smart Prompt")
        promptLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        promptLabel.textColor = SettingsPalette.textPrimary

        promptTextView.font = NSFont.systemFont(ofSize: 12)
        promptTextView.textColor = SettingsPalette.textPrimary
        promptTextView.insertionPointColor = .white
        promptTextView.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.7)
        promptTextView.drawsBackground = true
        promptTextView.isRichText = false
        promptTextView.isAutomaticQuoteSubstitutionEnabled = false
        promptTextView.delegate = self

        let promptScroll = NSScrollView()
        promptScroll.drawsBackground = false
        promptScroll.hasVerticalScroller = true
        promptScroll.borderType = .bezelBorder
        promptScroll.documentView = promptTextView
        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let promptStack = NSStackView(views: [promptLabel, promptScroll])
        promptStack.orientation = .vertical
        promptStack.alignment = .leading
        promptStack.spacing = 6
        promptStack.translatesAutoresizingMaskIntoConstraints = false
        promptContainer.addSubview(promptStack)

        NSLayoutConstraint.activate([
            promptStack.leadingAnchor.constraint(equalTo: promptContainer.leadingAnchor),
            promptStack.trailingAnchor.constraint(equalTo: promptContainer.trailingAnchor),
            promptStack.topAnchor.constraint(equalTo: promptContainer.topAnchor),
            promptStack.bottomAnchor.constraint(equalTo: promptContainer.bottomAnchor),
            promptScroll.widthAnchor.constraint(equalTo: promptContainer.widthAnchor)
        ])

        card.stack.addArrangedSubview(makeKeyValueRow(title: "Mode", trailing: modeControl))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(modeDescriptionLabel)
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(promptContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func refresh() {
        modeControl.selectedSegment = appModel.transcriptionMode == .verbatim ? 0 : 1
        modeDescriptionLabel.stringValue = appModel.transcriptionMode.description

        let promptIsFocused = promptTextView.window?.firstResponder === promptTextView
        if !promptIsFocused, promptTextView.string != appModel.smartPrompt {
            promptTextView.string = appModel.smartPrompt
        }

        let showingPrompt = appModel.transcriptionMode == .smart
        promptContainer.isHidden = !showingPrompt
    }

    @objc
    private func modeChanged(_ sender: NSSegmentedControl) {
        appModel.transcriptionMode = sender.selectedSegment == 0 ? .verbatim : .smart
        refresh()
        onNeedsRefresh?()
    }

    func textDidChange(_ notification: Notification) {
        appModel.smartPrompt = promptTextView.string
    }
}

@MainActor
private final class PermissionsSettingsPaneView: SettingsPaneView {
    private let microphoneStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private lazy var microphoneButton = makePrimaryButton("Grant", action: #selector(handleMicrophoneButton))
    private lazy var accessibilityButton = makePrimaryButton("Enable", action: #selector(handleAccessibilityButton))
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    override init(appModel: AppModel) {
        super.init(appModel: appModel)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        let card = makeCardView()
        stack.addArrangedSubview(card)

        microphoneStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        accessibilityStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        card.stack.addArrangedSubview(makeKeyValueRow(title: "Microphone", trailing: microphoneStatusLabel))
        card.stack.addArrangedSubview(makeKeyValueRow(title: "", trailing: microphoneButton))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(makeKeyValueRow(title: "Accessibility", trailing: accessibilityStatusLabel))
        card.stack.addArrangedSubview(makeKeyValueRow(title: "", trailing: accessibilityButton))

        messageLabel.font = NSFont.systemFont(ofSize: 12)
        messageLabel.textColor = SettingsPalette.textSecondary
        messageLabel.maximumNumberOfLines = 4
        stack.addArrangedSubview(messageLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func refresh() {
        microphoneStatusLabel.stringValue = appModel.microphoneAuthorized ? "Enabled" : "Not Granted"
        microphoneStatusLabel.textColor = appModel.microphoneAuthorized ? NSColor.systemGreen : NSColor.systemOrange

        accessibilityStatusLabel.stringValue = appModel.accessibilityAuthorized ? "Enabled" : "Required (Not Granted)"
        accessibilityStatusLabel.textColor = appModel.accessibilityAuthorized ? NSColor.systemGreen : NSColor.systemOrange

        microphoneButton.isHidden = appModel.microphoneAuthorized
        accessibilityButton.isHidden = appModel.accessibilityAuthorized

        messageLabel.stringValue = appModel.lastError ?? appModel.transientMessage ?? ""
        messageLabel.isHidden = messageLabel.stringValue.isEmpty
    }

    @objc
    private func handleMicrophoneButton() {
        Task {
            await appModel.microphonePermissionButtonTapped()
            await MainActor.run {
                self.onNeedsRefresh?()
            }
        }
    }

    @objc
    private func handleAccessibilityButton() {
        appModel.accessibilityPermissionButtonTapped()
        onNeedsRefresh?()
    }
}

@MainActor
private final class HistorySettingsPaneView: SettingsPaneView {
    private let retentionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pathLabel = NSTextField(wrappingLabelWithString: "")
    private let entriesStack = NSStackView()

    override init(appModel: AppModel) {
        super.init(appModel: appModel)

        for mode in HistoryRetentionMode.allCases {
            retentionPopup.addItem(withTitle: mode.displayName)
            retentionPopup.lastItem?.representedObject = mode.rawValue
        }
        retentionPopup.target = self
        retentionPopup.action = #selector(retentionChanged(_:))

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let controlsCard = makeCardView()
        container.addArrangedSubview(controlsCard)

        pathLabel.font = NSFont.systemFont(ofSize: 11)
        pathLabel.textColor = SettingsPalette.textSecondary
        pathLabel.maximumNumberOfLines = 2

        let openFolderButton = makePrimaryButton("Open Folder", action: #selector(openFolder))

        controlsCard.stack.addArrangedSubview(makeKeyValueRow(title: "Retention", trailing: retentionPopup))
        controlsCard.stack.addArrangedSubview(makeRowLine())
        controlsCard.stack.addArrangedSubview(makeKeyValueRow(title: "History Path", trailing: openFolderButton))
        controlsCard.stack.addArrangedSubview(pathLabel)

        let historyCard = makeCardView()
        container.addArrangedSubview(historyCard)

        let recentLabel = NSTextField(labelWithString: "Recent Transcripts")
        recentLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        recentLabel.textColor = SettingsPalette.textPrimary
        historyCard.stack.addArrangedSubview(recentLabel)
        historyCard.stack.addArrangedSubview(makeRowLine())

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        entriesStack.orientation = .vertical
        entriesStack.alignment = .leading
        entriesStack.spacing = 10
        entriesStack.translatesAutoresizingMaskIntoConstraints = false

        let entriesContainer = NSView()
        entriesContainer.translatesAutoresizingMaskIntoConstraints = false
        entriesContainer.addSubview(entriesStack)

        NSLayoutConstraint.activate([
            entriesStack.leadingAnchor.constraint(equalTo: entriesContainer.leadingAnchor),
            entriesStack.trailingAnchor.constraint(equalTo: entriesContainer.trailingAnchor),
            entriesStack.topAnchor.constraint(equalTo: entriesContainer.topAnchor),
            entriesStack.bottomAnchor.constraint(equalTo: entriesContainer.bottomAnchor),
            entriesStack.widthAnchor.constraint(equalTo: entriesContainer.widthAnchor)
        ])

        scrollView.documentView = entriesContainer
        historyCard.stack.addArrangedSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func refresh() {
        for item in retentionPopup.itemArray where (item.representedObject as? String) == appModel.historyRetentionMode.rawValue {
            retentionPopup.select(item)
            break
        }

        pathLabel.stringValue = appModel.historyDirectoryDisplayPath
        rebuildRecentEntries()
    }

    private func rebuildRecentEntries() {
        entriesStack.arrangedSubviews.forEach {
            entriesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let entries = Array(appModel.recentTranscriptHistoryEntries.prefix(10))
        guard !entries.isEmpty else {
            let emptyLabel = makeDescriptionLabel("No transcripts yet.")
            entriesStack.addArrangedSubview(emptyLabel)
            return
        }

        for (index, entry) in entries.enumerated() {
            let entryView = makeHistoryEntryView(entry)
            entriesStack.addArrangedSubview(entryView)

            if index < entries.count - 1 {
                entriesStack.addArrangedSubview(makeRowLine())
            }
        }
    }

    private func makeHistoryEntryView(_ entry: TranscriptHistoryEntry) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4

        let timestamp = NSTextField(labelWithString: appModel.historyTimestampText(for: entry))
        timestamp.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        timestamp.textColor = SettingsPalette.textSecondary

        let metadata = NSTextField(wrappingLabelWithString: appModel.historyMetadataText(for: entry))
        metadata.font = NSFont.systemFont(ofSize: 11)
        metadata.textColor = SettingsPalette.textSecondary
        metadata.maximumNumberOfLines = 2

        let transcript = NSTextField(wrappingLabelWithString: entry.transcript.isEmpty ? "Transcript not retained." : entry.transcript)
        transcript.font = NSFont.systemFont(ofSize: 12)
        transcript.textColor = SettingsPalette.textPrimary
        transcript.maximumNumberOfLines = 2

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let copyButton = CallbackButton.link(title: "Copy") { [weak self] in
            self?.appModel.copyTranscriptHistoryButtonTapped(entry.id)
            self?.onNeedsRefresh?()
        }
        actions.addArrangedSubview(copyButton)

        if entry.audioRelativePath != nil {
            let playButton = CallbackButton.link(title: "Play") { [weak self] in
                self?.appModel.playHistoryAudioButtonTapped(entry.id)
                self?.onNeedsRefresh?()
            }
            actions.addArrangedSubview(playButton)
        }

        let topRow = NSStackView(views: [timestamp, NSView(), actions])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8
        if let spacer = topRow.arrangedSubviews[safe: 1] {
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        container.addArrangedSubview(topRow)
        container.addArrangedSubview(metadata)
        container.addArrangedSubview(transcript)
        return container
    }

    @objc
    private func retentionChanged(_ sender: NSPopUpButton) {
        guard
            let rawValue = sender.selectedItem?.representedObject as? String,
            let mode = HistoryRetentionMode(rawValue: rawValue)
        else { return }
        appModel.historyRetentionMode = mode
        onNeedsRefresh?()
    }

    @objc
    private func openFolder() {
        appModel.openHistoryFolderButtonTapped()
        onNeedsRefresh?()
    }
}

@MainActor
private final class AboutSettingsPaneView: SettingsPaneView {
    private let versionLabel = NSTextField(labelWithString: "")

    override init(appModel: AppModel) {
        super.init(appModel: appModel)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        let card = makeCardView()
        stack.addArrangedSubview(card)

        let appNameLabel = NSTextField(labelWithString: "Gloam")
        appNameLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        appNameLabel.textColor = SettingsPalette.textPrimary

        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = SettingsPalette.textSecondary

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let textStack = NSStackView(views: [appNameLabel, versionLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        let headerRow = NSStackView(views: [iconView, textStack])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10

        let updatesButton = makePrimaryButton("Check for Updates", action: #selector(checkForUpdates))
        let websiteButton = CallbackButton.link(title: "aayush.art") {
            guard let url = URL(string: "https://aayush.art") else { return }
            NSWorkspace.shared.open(url)
        }
        let githubButton = CallbackButton.link(title: "GitHub") {
            guard let url = URL(string: "https://github.com/Aayush9029") else { return }
            NSWorkspace.shared.open(url)
        }

        let linksRow = NSStackView(views: [websiteButton, githubButton])
        linksRow.orientation = .horizontal
        linksRow.alignment = .centerY
        linksRow.spacing = 12

        card.stack.addArrangedSubview(headerRow)
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(makeKeyValueRow(title: "Updates", trailing: updatesButton))
        card.stack.addArrangedSubview(makeRowLine())
        card.stack.addArrangedSubview(linksRow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func refresh() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        versionLabel.stringValue = "Version \(version) (\(build))"
    }

    @objc
    private func checkForUpdates() {
        (NSApp.delegate as? AppDelegate)?.updaterController.updater.checkForUpdates()
    }
}

private final class SettingsSurfaceView: NSView {
    private let gradientLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -8)

        gradientLayer.colors = [
            NSColor(calibratedRed: 0.37, green: 0.39, blue: 0.42, alpha: 0.96).cgColor,
            NSColor(calibratedRed: 0.31, green: 0.33, blue: 0.36, alpha: 0.97).cgColor,
            NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.33, alpha: 0.98).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }
}

private final class SettingsSidebarItemControl: NSControl {
    let section: SettingsSectionID

    private let iconBubble = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    var isSelectedItem = false {
        didSet {
            updateAppearance()
        }
    }

    init(section: SettingsSectionID) {
        self.section = section
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            heightAnchor.constraint(equalToConstant: 34)
        ])

        iconBubble.wantsLayer = true
        iconBubble.layer?.cornerRadius = 7
        iconBubble.translatesAutoresizingMaskIntoConstraints = false
        iconBubble.addSubview(iconView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        iconView.contentTintColor = .white

        NSLayoutConstraint.activate([
            iconBubble.widthAnchor.constraint(equalToConstant: 21),
            iconBubble.heightAnchor.constraint(equalToConstant: 21),
            iconView.centerXAnchor.constraint(equalTo: iconBubble.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBubble.centerYAnchor)
        ])

        titleLabel.stringValue = section.title
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(iconBubble)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(spacer)

        iconBubble.layer?.backgroundColor = section.tintColor.cgColor
        iconView.image = NSImage(systemSymbolName: section.symbolName, accessibilityDescription: section.title)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        sendAction(action, to: target)
    }

    private func updateAppearance() {
        layer?.backgroundColor = isSelectedItem ? SettingsPalette.selectedFill.cgColor : NSColor.clear.cgColor
        titleLabel.textColor = isSelectedItem ? SettingsPalette.textPrimary : NSColor(calibratedWhite: 0.82, alpha: 1)
    }
}

private final class SettingsCardView: NSView {
    let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = SettingsPalette.cardFill.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = SettingsPalette.cardBorder.cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class CallbackButton: NSButton {
    private var handler: (() -> Void)?

    static func link(title: String, handler: @escaping () -> Void) -> CallbackButton {
        let button = CallbackButton(title: title, bordered: false, handler: handler)
        button.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        button.contentTintColor = NSColor.systemTeal
        return button
    }

    init(title: String, bordered: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(trigger)
        isBordered = bordered
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc
    private func trigger() {
        handler?()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
