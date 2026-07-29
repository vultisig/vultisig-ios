//
//  SettingsCommonOptionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

struct SettingsCommonOptionView: View {
    let icon: ImageResource?
    let title: String
    let subtitle: String?
    let description: String?
    let type: SettingsOptionViewType

    init(
        icon: ImageResource?,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        type: SettingsOptionViewType = .normal
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.type = type
    }

    var body: some View {
        SettingsOptionView(
            icon: icon,
            title: title,
            subtitle: subtitle,
            type: type,
            trailingView: { trailingView }
        )
    }

    @ViewBuilder
    var trailingView: some View {
        if let description {
            Text(description)
                .font(Theme.fonts.subtitle)
        }

        Icon(
            .chevronRight,
            color: Theme.colors.textTertiary,
            size: 16
        )
    }
}
