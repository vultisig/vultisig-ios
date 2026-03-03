//
//  FontStyle.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

enum FontStyle: String, CaseIterable {
    case brockmanBold
    case brockmanMedium
    case brockmanRegular
    case brockmanSemibold
    case satoshiMedium

    func size(_ size: CGFloat) -> Font {
        return Font.custom(fontName, size: size)
    }

    #if os(iOS)
    func uiFont(_ size: CGFloat) -> UIFont {
        UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
    }
    #endif

    var fontName: String {
        switch self {
        case .brockmanBold:
            "Brockmann-Bold"
        case .brockmanMedium:
            "Brockmann-Medium"
        case .brockmanRegular:
            "Brockmann-Regular"
        case .brockmanSemibold:
            "Brockmann-Semibold"
        case .satoshiMedium:
            "Satoshi-Medium"
        }
    }
}
