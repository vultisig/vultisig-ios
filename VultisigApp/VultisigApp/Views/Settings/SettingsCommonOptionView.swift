//
//  SettingsCommonOptionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

struct SettingsCommonOptionView: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let description: String?
    let type: SettingsOptionViewType
    let showSeparator: Bool
    
    init(
        icon: String?,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        type: SettingsOptionViewType = .normal,
        showSeparator: Bool = true
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.type = type
        self.showSeparator = showSeparator
    }
    
    var body: some View {
        SettingsOptionView(
            icon: icon,
            title: title,
            subtitle: subtitle,
            type: type,
            showSeparator: showSeparator,
            trailingView: { trailingView }
        )
    }
    
    @ViewBuilder
    var trailingView: some View {
        if let description {
            Text(description)
                .font(Theme.fonts.footnote)
        }
        
        Icon(
            named: "chevron-right",
            color: Theme.colors.textTertiary,
            size: 16
        )
    }
}
