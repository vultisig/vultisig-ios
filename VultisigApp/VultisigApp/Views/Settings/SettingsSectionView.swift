//
//  SettingsSectionView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI

struct SettingsSectionView<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.localized)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)

            SettingsSectionContainerView {
                VStack(spacing: .zero) {
                    content()
                }
            }
        }
    }
}
