//
//  WidgetTheme.swift
//  VultisigWidgets
//

import SwiftUI
import VultisigUIResources

enum WidgetTheme {
    static let background = Color(red: 2 / 255, green: 18 / 255, blue: 43 / 255)
    static let primaryText = Color(red: 240 / 255, green: 244 / 255, blue: 252 / 255)
    static let secondaryText = Color(red: 201 / 255, green: 214 / 255, blue: 232 / 255)
    static let tertiaryText = Color(red: 130 / 255, green: 149 / 255, blue: 174 / 255)
    static let separator = Color(red: 17 / 255, green: 40 / 255, blue: 74 / 255)
    static let positive = Color(red: 19 / 255, green: 200 / 255, blue: 157 / 255)
    static let negative = Color(red: 255 / 255, green: 92 / 255, blue: 92 / 255)
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
