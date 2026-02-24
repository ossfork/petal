import SwiftUI
import UI

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

