//
//  SettingsSectionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

struct SettingsSectionView<Content: View>: View {
    let title: String
    let style: CommonListStyle
    let content: () -> Content

    init(title: String, style: CommonListStyle = .outlined, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.style = style
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            caption

            VStack(spacing: .zero) {
                content()
            }
            .commonListContainer(style: style)
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch style {
        case .outlined:
            Text(title.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
        case .flush:
            Text(title.localized)
                .settingsText(.caption)
                .foregroundStyle(Theme.colors.textTertiary)
        }
    }
}
