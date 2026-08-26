//
//  WidgetBrandMark.swift
//  VultisigWidgets
//

import SwiftUI

struct WidgetBrandMark: View {
    let size: CGFloat

    var body: some View {
        Image("logo-outline")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(WidgetTheme.primaryText)
            .frame(width: size, height: size)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}
