//
//  CommonListHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

struct CommonListHeaderView: View {
    let title: String
    let subtitle: String?
    let paddingTop: CGFloat?

    init(title: String, subtitle: String? = nil, paddingTop: CGFloat? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.paddingTop = paddingTop
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(subtitle != nil ? Theme.colors.textPrimary : Theme.colors.textTertiary)

            if let subtitle {
                Text(subtitle)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
        .background(Theme.colors.bgPrimary)
        .padding(.top, paddingTop ?? 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .plainListItem()
    }
}

#Preview {
    CommonListHeaderView(title: "Test")
}
