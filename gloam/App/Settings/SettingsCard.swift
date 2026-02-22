import SwiftUI

let settingsContentWidth: Double = 540

// MARK: - Alignment Guide

extension HorizontalAlignment {
    private enum SettingsSectionLabelAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.leading]
        }
    }

    static let settingsSectionLabel = HorizontalAlignment(SettingsSectionLabelAlignment.self)
}

// MARK: - SettingsSection

struct SettingsSection: View {
    private struct LabelWidthPreferenceKey: PreferenceKey {
        typealias Value = Double
        static var defaultValue = 0.0
        static func reduce(value: inout Double, nextValue: () -> Double) {
            let next = nextValue()
            value = next > value ? next : value
        }
    }

    private struct LabelOverlay: View {
        var body: some View {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: LabelWidthPreferenceKey.self, value: geometry.size.width)
            }
        }
    }

    struct LabelWidthModifier: ViewModifier {
        @Binding var maximumWidth: Double
        func body(content: Content) -> some View {
            content
                .onPreferenceChange(LabelWidthPreferenceKey.self) { newMaximumWidth in
                    maximumWidth = newMaximumWidth
                }
        }
    }

    let label: AnyView
    let content: AnyView
    let bottomDivider: Bool
    let verticalAlignment: VerticalAlignment

    init(
        bottomDivider: Bool = false,
        verticalAlignment: VerticalAlignment = .firstTextBaseline,
        label: @escaping () -> some View,
        @ViewBuilder content: @escaping () -> some View
    ) {
        self.label = AnyView(label().overlay(LabelOverlay()))
        self.bottomDivider = bottomDivider
        self.verticalAlignment = verticalAlignment
        self.content = AnyView(VStack(alignment: .leading, spacing: 6) { content() })
    }

    init(
        _ title: String,
        bottomDivider: Bool = false,
        verticalAlignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder content: @escaping () -> some View
    ) {
        self.init(
            bottomDivider: bottomDivider,
            verticalAlignment: verticalAlignment,
            label: {
                Text(title)
                    .font(.system(size: 13))
            },
            content: content
        )
    }

    var body: some View {
        HStack(alignment: verticalAlignment) {
            label
                .alignmentGuide(.settingsSectionLabel) { $0[.trailing] }
            content
            Spacer()
        }
    }
}

// MARK: - SettingsSectionBuilder

@resultBuilder
struct SettingsSectionBuilder {
    static func buildBlock(_ sections: SettingsSection...) -> [SettingsSection] {
        sections
    }

    static func buildBlock(_ sections: [SettingsSection]...) -> [SettingsSection] {
        sections.flatMap { $0 }
    }

    static func buildExpression(_ section: SettingsSection) -> [SettingsSection] {
        [section]
    }

    static func buildExpression(_ sections: [SettingsSection]) -> [SettingsSection] {
        sections
    }

    static func buildOptional(_ sections: [SettingsSection]?) -> [SettingsSection] {
        sections ?? []
    }
}

// MARK: - SettingsContainer

struct SettingsContainer: View {
    private let sectionBuilder: () -> [SettingsSection]
    private let minimumLabelWidth: Double
    @State private var maximumLabelWidth = 0.0

    init(
        minimumLabelWidth: Double = 0,
        @SettingsSectionBuilder builder: @escaping () -> [SettingsSection]
    ) {
        self.sectionBuilder = builder
        self.minimumLabelWidth = minimumLabelWidth
    }

    var body: some View {
        let sections = sectionBuilder()

        VStack(alignment: .settingsSectionLabel, spacing: 18) {
            ForEach(0..<sections.count, id: \.self) { index in
                viewForSection(sections, index: index)
            }
        }
        .modifier(SettingsSection.LabelWidthModifier(maximumWidth: $maximumLabelWidth))
        .frame(width: settingsContentWidth, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 30)
    }

    @ViewBuilder
    private func viewForSection(_ sections: [SettingsSection], index: Int) -> some View {
        sections[index]
        if index != sections.count - 1 && sections[index].bottomDivider {
            Divider()
                .frame(width: settingsContentWidth, height: 8)
                .alignmentGuide(.settingsSectionLabel) {
                    $0[.leading] + max(minimumLabelWidth, maximumLabelWidth)
                }
        }
    }
}

// MARK: - Setting Description

extension View {
    func settingDescription() -> some View {
        font(.system(size: 11.0))
            .foregroundStyle(.secondary)
    }
}
