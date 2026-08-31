//
//  WidgetTheme.swift
//  VultisigWidgets
//

import SwiftUI
import VultisigDesignSystem
import VultisigUIResources

enum WidgetTheme {
    static let background = Theme.colors.bgPrimary
    static let primaryText = Theme.colors.textPrimary
    static let secondaryText = Theme.colors.textSecondary
    static let tertiaryText = Theme.colors.textTertiary
    static let separator = Theme.colors.border
    static let positive = Theme.colors.alertSuccess
    static let negative = Theme.colors.alertError
    static let iconFallbackBackground = primaryText

    static func labelFont(size: CGFloat) -> Font {
        VultisigFont.brockmannMedium.font(size: size)
    }

    static func priceFont(size: CGFloat) -> Font {
        VultisigFont.satoshiMedium.font(size: size).monospacedDigit()
    }

    static func iconFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
}
