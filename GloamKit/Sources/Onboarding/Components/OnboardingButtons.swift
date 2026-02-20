import SwiftUI

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

struct OnboardingActionBar: View {
    let showBack: Bool
    let backAction: (() -> Void)?
    let primaryTitle: String
    let primaryDisabled: Bool
    let primaryAction: () -> Void

    init(
        showBack: Bool = false,
        backAction: (() -> Void)? = nil,
        primaryTitle: String,
        primaryDisabled: Bool = false,
        primaryAction: @escaping () -> Void
    ) {
        self.showBack = showBack
        self.backAction = backAction
        self.primaryTitle = primaryTitle
        self.primaryDisabled = primaryDisabled
        self.primaryAction = primaryAction
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(.white.opacity(0.08))

            HStack(spacing: 10) {
                if showBack, let backAction {
                    ComposeSecondaryButton("Back", systemImage: "chevron.left") {
                        backAction()
                    }
                }

                Spacer()

                ComposePrimaryButton(primaryTitle) {
                    primaryAction()
                }
                .disabled(primaryDisabled)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(.regularMaterial)
            .overlay {
                Color.black.opacity(0.22)
                    .allowsHitTesting(false)
            }
        }
    }
}
