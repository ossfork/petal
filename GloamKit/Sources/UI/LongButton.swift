import SwiftUI

// MARK: - Button Variant

public enum LongButtonVariant {
    case primary
    case secondary
    case destructive
    case custom(backgroundColor: Color, textColor: Color)

    var backgroundColor: Color {
        switch self {
        case .primary: .blue
        case .secondary: .primary.opacity(0.15)
        case .destructive: .red
        case .custom(let bg, _): bg
        }
    }

    var textColor: Color {
        switch self {
        case .primary: .white
        case .secondary: .primary
        case .destructive: .white
        case .custom(_, let text): text
        }
    }
}

// MARK: - LongButton

public struct LongButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let text: String
    let symbol: String?
    let variant: LongButtonVariant
    let verticalPadding: CGFloat
    let action: () -> Void

    public init(
        _ text: String,
        symbol: String? = nil,
        variant: LongButtonVariant = .primary,
        verticalPadding: CGFloat = 12,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.symbol = symbol
        self.variant = variant
        self.verticalPadding = verticalPadding
        self.action = action
    }

    public var body: some View {
        Button(action: { action() }) {
            buttonContent
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .scaleEffect(isHovering && isEnabled ? 1.02 : 1)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var buttonContent: some View {
        Group {
            if let symbol {
                Label(text, systemImage: symbol)
            } else {
                Text(text)
            }
        }
        .foregroundColor(variant.textColor)
        .font(.title3.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, verticalPadding)
        .background { buttonBackground }
        .contentShape(.capsule)
    }

    private var resolvedBackgroundColor: Color {
        switch variant {
        case .secondary:
            return .primary.opacity(colorScheme == .dark ? 0.25 : 0.15)
        default:
            return variant.backgroundColor
        }
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(resolvedBackgroundColor.opacity(0.8))
                .glassEffect(in: .capsule)
        } else {
            resolvedBackgroundColor
                .clipShape(.capsule)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        LongButton("Primary", variant: .primary) {}
        LongButton("Secondary", variant: .secondary) {}
        LongButton("Destructive", variant: .destructive) {}
        LongButton("With Symbol", symbol: "star.fill", variant: .primary) {}
        LongButton("Disabled", variant: .primary) {}
            .disabled(true)
    }
    .padding()
    .frame(width: 300)
    .preferredColorScheme(.dark)
}
#endif
