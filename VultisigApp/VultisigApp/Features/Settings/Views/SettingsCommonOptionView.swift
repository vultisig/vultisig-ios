//
//  SettingsCommonOptionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

/// The chevron glyph a settings row ends with; the design draws two.
enum SettingsChevron {
    case small
    case regular

    var image: ImageResource {
        switch self {
        case .small: .iconChevronRightSmall
        case .regular: .arrowsChevronRight
        }
    }
}

struct SettingsCommonOptionView: View {
    let icon: ImageResource?
    let title: String
    let subtitle: String?
    let description: String?
    let type: SettingsOptionViewType
    let titleStyle: SettingsTextStyle
    let chevron: SettingsChevron

    init(
        icon: ImageResource?,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        type: SettingsOptionViewType = .normal,
        titleStyle: SettingsTextStyle = .bodyS,
        chevron: SettingsChevron = .small
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.type = type
        self.titleStyle = titleStyle
        self.chevron = chevron
    }

    var body: some View {
        SettingsOptionView(
            icon: icon,
            title: title,
            subtitle: subtitle,
            type: type,
            titleStyle: titleStyle,
            trailingView: { trailingView }
        )
    }

    @ViewBuilder
    var trailingView: some View {
        if let description {
            Text(description)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textPrimary)
        }

        SettingsChevronIcon(chevron: chevron)
    }
}

/// A row's trailing chevron at the design's size and colour.
struct SettingsChevronIcon: View {
    var chevron: SettingsChevron = .small

    var body: some View {
        Icon(chevron.image, color: Theme.colors.textTertiary, size: 16)
    }
}
