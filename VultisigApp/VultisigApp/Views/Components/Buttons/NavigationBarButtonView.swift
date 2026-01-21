//
//  NavigationBarButtonView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/08/2025.
//

import SwiftUI

struct NavigationBarButtonView: View {
    let title: String

    var body: some View {
        Text(title)
            .foregroundStyle(Theme.colors.primaryAccent4)
            .font(Theme.fonts.bodySRegular)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 99).fill(Theme.colors.bgButtonSecondary))
    }
}
