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
