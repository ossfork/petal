import AppKit
import KeyboardShortcuts
import PermissionsClient
import Shared
import SwiftUI

public struct SetupView: View {
    @Bindable var model: SetupModel
    @State private var hasStarted = false
    @State private var animating = false

    public init(model: SetupModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !hasStarted {
                            topSection
                                .slideIn(active: animating)
                        }

                        stageCard
                            .slideIn(active: animating, delay: 0.2)

                        feedbackSection
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 28)
                }
                .scrollIndicators(.hidden)

                Divider()
                    .overlay(.white.opacity(0.08))

                actionBar
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .background(.regularMaterial)
                    .overlay(.black.opacity(0.22))
            }
            .frame(width: 900, height: 560)
            .background {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.black.opacity(0.28))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 24, y: 12)
            .padding(18)
        }
        .frame(width: 900, height: 560)
        .preferredColorScheme(.dark)
        .onAppear {
            animating = true
            model.windowAppeared()
            DispatchQueue.main.async {
                ensureSetupWindowsAreVisible()
            }
        }
        .onChange(of: model.selectedModelID) { _, _ in
            model.selectedModelChanged()
        }
    }

    private var backgroundLayer: some View {
        Group {
            if NSImage(named: "blackhole") != nil {
                Image("blackhole")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.12)
                    .saturation(0.72)
                    .blur(radius: 96)
                    .opacity(0.86)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.10, blue: 0.22),
                        Color(red: 0.05, green: 0.04, blue: 0.14),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay {
            LinearGradient(
                colors: [
                    .black.opacity(0.25),
                    .black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var topSection: some View {
        VStack(spacing: 10) {
            if NSImage(named: "appIcon") != nil {
                Image("appIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .shadow(radius: 12)
            } else {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 74))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }

            Text("Welcome to Gloam")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("On-device transcription with a Compose-inspired setup flow.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var stageCard: some View {
        if !hasStarted {
            welcomeCard
        } else {
            switch model.step {
            case .model:
                modelCard
            case .shortcut:
                shortcutCard
            case .download:
                permissionAndDownloadCard
            }
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            onboardingFeatureRow(
                symbol: "sparkles",
                title: "Fast everywhere",
                description: "Start recording instantly from your global shortcut."
            )

            onboardingFeatureRow(
                symbol: "slider.horizontal.3",
                title: "Choose your model",
                description: "Pick the model size that fits your speed and quality needs."
            )

            onboardingFeatureRow(
                symbol: "lock.shield",
                title: "Private by default",
                description: "Transcription runs locally on your Mac using downloaded models."
            )
        }
        .onboardingCard()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeader(
                symbol: "externaldrive.fill",
                title: "Choose your model",
                description: "Select the local model that fits your speed and quality balance.",
                layout: .vertical
            )

            VStack(spacing: 10) {
                ForEach(ModelOption.allCases) { option in
                    modelOptionCard(option)
                }
            }

            if let option = model.selectedModelOption {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Label(option.sizeLabel, systemImage: "externaldrive")
                        Label(option.rawValue, systemImage: "cpu")
                    }
                    .font(.caption)

                    Text(option.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
        .onboardingCard()
    }

    private func modelOptionCard(_ option: ModelOption) -> some View {
        let isSelected = option.rawValue == model.selectedModelID

        return Button {
            model.selectedModelID = option.rawValue
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(option.displayName)
                            .font(.headline)

                        if option.isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .capsulePill(
                                    horizontalPadding: 8,
                                    verticalPadding: 4,
                                    fill: Color.green.opacity(0.22)
                                )
                                .foregroundStyle(.green)
                        }
                    }

                    Text(option.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(option.sizeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.26))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeader(
                symbol: "keyboard.badge.ellipsis.fill",
                title: "Set your shortcut",
                description: "Use a key combo you can hit quickly in any app.",
                layout: .vertical
            )

            VStack(alignment: .leading, spacing: 12) {
                KeyboardShortcuts.Recorder("Push to talk", name: .pushToTalk)

                Text(model.shortcutDisplayText)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }

                Text(model.shortcutUsageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onboardingCard()
    }

    private var permissionAndDownloadCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            permissionIconStack
                .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text("Enable permissions")
                    .font(.title3.bold())
                    .fontDesign(.rounded)

                Text("Microphone is required. Accessibility is optional and enables auto-paste to the focused app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                permissionStatusChip(
                    title: "Microphone",
                    isGranted: model.microphoneAuthorized,
                    required: true
                )

                permissionStatusChip(
                    title: "Accessibility",
                    isGranted: model.accessibilityAuthorized,
                    required: false
                )
            }

            HStack(spacing: 10) {
                if !model.microphoneAuthorized {
                    ComposeSecondaryButton(model.microphonePermissionActionTitle, systemImage: "mic.fill") {
                        Task { await model.microphonePermissionButtonTapped() }
                    }
                }

                if !model.accessibilityAuthorized {
                    ComposeSecondaryButton("Enable Accessibility", systemImage: "figure.wave") {
                        model.accessibilityPermissionButtonTapped()
                    }
                }
            }

            Divider()
                .overlay(.white.opacity(0.08))

            Label("Model: \(model.currentModelSummary)", systemImage: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("Models folder: \(model.modelsDirectoryDisplayPath)", systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 10) {
                Picker("History Retention", selection: Binding(
                    get: { model.historyRetentionMode },
                    set: { model.historyRetentionMode = $0 }
                )) {
                    ForEach(HistoryRetentionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Button("Open History Folder") {
                    model.openHistoryFolderButtonTapped()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            if model.isDownloadingModel || model.downloadProgress > 0 || !model.downloadStatus.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.downloadStatus.isEmpty ? "Download status" : model.downloadStatus)
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text(model.downloadSummaryText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: model.downloadProgress)
                }
                .padding(12)
                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onboardingCard()
    }

    private var permissionIconStack: some View {
        ZStack {
            if NSImage(named: "accessibility") != nil {
                Image("accessibility")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .offset(y: -26)
            } else {
                Image(systemName: "accessibility.fill")
                    .font(.system(size: 40))
                    .offset(y: -26)
            }

            if NSImage(named: "appIcon") != nil {
                Image("appIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(radius: 8)
                    .offset(y: 20)
            } else {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 58))
                    .offset(y: 20)
            }
        }
        .frame(height: 130)
    }

    private func permissionStatusChip(title: String, isGranted: Bool, required: Bool) -> some View {
        let statusColor: Color = isGranted ? .green : (required ? .red : .orange)
        let statusText = isGranted ? "Enabled" : (required ? "Required" : "Optional")

        return HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle")
            Text("\(title): \(statusText)")
        }
        .font(.caption.weight(.semibold))
        .capsulePill(
            horizontalPadding: 10,
            verticalPadding: 6,
            fill: statusColor.opacity(0.2)
        )
        .foregroundStyle(statusColor)
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasStarted, let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if hasStarted, let message = model.transientMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if showBackButton {
                ComposeSecondaryButton("Back", systemImage: "chevron.left") {
                    backButtonTapped()
                }
            }

            Spacer()

            ComposePrimaryButton(primaryButtonTitle) {
                primaryButtonTapped()
            }
            .disabled(primaryButtonDisabled)
        }
    }

    private var showBackButton: Bool {
        hasStarted && (model.canGoBack || model.step == .model)
    }

    private var primaryButtonTitle: String {
        hasStarted ? model.primaryButtonTitle : "Get Started"
    }

    private var primaryButtonDisabled: Bool {
        hasStarted ? model.primaryButtonDisabled : false
    }

    private func onboardingFeatureRow(symbol: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func backButtonTapped() {
        if model.step == .model {
            withAnimation(.easeInOut) {
                hasStarted = false
            }
        } else {
            model.backButtonTapped()
        }
    }

    private func primaryButtonTapped() {
        if !hasStarted {
            withAnimation(.easeInOut(duration: 0.35)) {
                hasStarted = true
            }
            return
        }

        Task { await model.primaryButtonTapped() }
    }

    private func ensureSetupWindowsAreVisible() {
        let setupTitles = Set(["Gloam Setup", "gloam Settings"])

        for window in NSApp.windows where setupTitles.contains(window.title) {
            guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
                window.center()
                continue
            }

            var origin = window.frame.origin
            let maxX = screenFrame.maxX - window.frame.width
            let maxY = screenFrame.maxY - window.frame.height

            if origin.x < screenFrame.minX || origin.x > maxX || origin.y < screenFrame.minY || origin.y > maxY {
                origin = NSPoint(
                    x: screenFrame.midX - (window.frame.width / 2),
                    y: screenFrame.midY - (window.frame.height / 2)
                )
                window.setFrameOrigin(origin)
            }
        }
    }
}

// MARK: - Helper Views

struct OnboardingHeader: View {
    enum Layout {
        case horizontal
        case vertical
    }

    @State private var animating = false
    let symbol: String?
    let title: String
    let description: String
    let layout: Layout

    init(symbol: String? = nil, title: String, description: String, layout: Layout = .horizontal) {
        self.symbol = symbol
        self.title = title
        self.description = description
        self.layout = layout
    }

    var body: some View {
        Group {
            switch layout {
            case .horizontal:
                HStack {
                    headerContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .vertical:
                VStack(alignment: .leading) {
                    headerContent
                }
            }
        }
        .onAppear {
            animating.toggle()
        }
    }

    private var headerContent: some View {
        Group {
            if let symbol {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .symbolVariant(.fill)
                    .symbolRenderingMode(.hierarchical)
                    .padding(4)
                    .padding(.leading, layout == .horizontal ? 0 : -4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                    .fontDesign(.rounded)

                Text(description)
                    .font(.headline)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
        }
        .slideIn(active: animating, delay: 0.3)
    }
}

struct ComposePrimaryButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(minWidth: 170)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .white : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(isEnabled ? 0.82 : 0.55))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
    }
}

struct ComposeSecondaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.headline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isEnabled ? .white : .secondary)
            .frame(minWidth: 120)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovering ? .white.opacity(0.16) : .white.opacity(0.09))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .scaleEffect(isHovering && isEnabled ? 1.02 : 1)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - View Extensions

extension View {
    func capsulePill<S: ShapeStyle>(
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        fill: S
    ) -> some View {
        self
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(fill, in: Capsule())
    }

    @ViewBuilder
    func slideIn(
        active: Bool,
        offset: CGFloat = 20,
        opacity: CGFloat = 0,
        blur: CGFloat = 0,
        scale: CGFloat = 1,
        delay: CGFloat = 0,
        duration: CGFloat = 1.0,
        animation: Animation = .easeIn
    ) -> some View {
        self
            .opacity(active ? 1 : opacity)
            .blur(radius: active ? 0 : blur)
            .offset(y: active ? 0 : offset)
            .scaleEffect(active ? 1 : scale)
            .animation(animation.speed(duration).delay(delay), value: active)
    }

    func onboardingCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(.black.opacity(0.3))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Welcome") {
    SetupView(model: .makePreview(step: .model))
}

#Preview("Step 1 - Model") {
    SetupView(model: .makePreview(step: .model))
}

#Preview("Step 2 - Shortcut") {
    SetupView(model: .makePreview(step: .shortcut))
}

#Preview("Step 3 - Permissions") {
    SetupView(
        model: .makePreview(step: .download) { model in
            model.microphonePermissionState = .notDetermined
            model.microphoneAuthorized = false
            model.accessibilityAuthorized = false
            model.transientMessage = "Grant permissions, then download your selected model."
        }
    )
}

#Preview("Step 3 - Downloading") {
    SetupView(
        model: .makePreview(step: .download) { model in
            model.microphonePermissionState = .authorized
            model.microphoneAuthorized = true
            model.accessibilityAuthorized = true
            model.isDownloadingModel = true
            model.downloadProgress = 0.42
            model.downloadStatus = "Downloading model..."
            model.downloadSpeedText = "11.2 MB/s"
        }
    )
}
#endif
