//
//  WidgetBrandMark.swift
//  VultisigWidgets
//

import SwiftUI
import VultisigUIResources

struct WidgetBrandMark: View {
    let size: CGFloat

    var body: some View {
        VultisigImage.logoOutline.image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(WidgetTheme.primaryText)
            .frame(width: size, height: size)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}
