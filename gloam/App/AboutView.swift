import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private let appInfo: AboutAppInfo
    var updatesModel: CheckForUpdatesModel?

    init(updatesModel: CheckForUpdatesModel? = nil) {
        appInfo = AboutAppInfo()
        self.updatesModel = updatesModel
    }

    var body: some View {
        VStack {
            Spacer()

            logoSection

            infoSection

            updateButton

            linksSection

            modelsSection

            copyrightInfo

            Spacer()
        }
        .frame(width: 280, height: 500 - 28)
        .background {
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    private var logoSection: some View {
        VStack(spacing: 2) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .padding()
            }

            Text("Gloam")
                .font(.title.bold())

            Text("Version \(appInfo.version), \(appInfo.buildYear)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom)
    }

    private var infoSection: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing) {
                AboutInfoRow(label: "Build", value: appInfo.build)
                AboutInfoRow(label: "Github", value: "Aayush9029")
                AboutInfoRow(label: "Designed By", value: "Aayush")
                AboutInfoRow(label: "Last Update", value: appInfo.lastUpdateChecked)
                AboutInfoRow(label: "Made in", value: "Toronto, CA")
            }
            .font(.subheadline)
            Spacer()
        }
    }

    private var updateButton: some View {
        Button("Check for Updates...") {
            updatesModel?.checkForUpdates()
        }
        .buttonStyle(.bordered)
        .disabled(!(updatesModel?.canCheckForUpdates ?? false))
        .padding()
    }

    private var linksSection: some View {
        VStack {
            ForEach(AboutLinkType.allCases) { linkType in
                Button(linkType.title) {
                    openURL(linkType.url)
                }
            }
        }
        .underline()
        .buttonStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var modelsSection: some View {
        VStack(spacing: 4) {
            Text("Models")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            ForEach(ModelCredit.allCases) { credit in
                Button(credit.title) {
                    openURL(credit.url)
                }
            }
        }
        .underline()
        .buttonStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private var copyrightInfo: some View {
        Text("Copyright \u{00A9} Aayush Pokharel, \(appInfo.buildYear)")
            .padding(.horizontal, 48)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}

// MARK: - Supporting Types

private struct AboutInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            HStack {
                Text(value)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .frame(width: 80)
        }
    }
}

private struct AboutAppInfo {
    let version: String
    let build: String
    let buildYear: String
    let lastUpdateChecked: String

    init() {
        let bundle = Bundle.main
        version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        buildYear = Calendar.current.component(.year, from: Date()).description

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        lastUpdateChecked = formatter.string(from: Date())
    }
}

private enum ModelCredit: String, CaseIterable, Identifiable {
    case mlxCommunity
    case argmax
    case mistral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mlxCommunity: return "MLX Community"
        case .argmax: return "Argmax (WhisperKit)"
        case .mistral: return "Mistral (Voxtral)"
        }
    }

    var url: URL {
        switch self {
        case .mlxCommunity: return URL(string: "https://huggingface.co/mlx-community")!
        case .argmax: return URL(string: "https://huggingface.co/argmaxinc")!
        case .mistral: return URL(string: "https://huggingface.co/mistralai")!
        }
    }
}

private enum AboutLinkType: String, CaseIterable, Identifiable {
    case website
    case github

    var id: String { rawValue }

    var title: String {
        switch self {
        case .website: return "aayush.art"
        case .github: return "GitHub"
        }
    }

    var url: URL {
        switch self {
        case .website: return URL(string: "https://aayush.art")!
        case .github: return URL(string: "https://github.com/Aayush9029/gloam")!
        }
    }
}
