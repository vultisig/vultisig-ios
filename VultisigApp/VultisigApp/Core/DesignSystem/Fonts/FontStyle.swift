//
//  FontStyle.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI
import VultisigUIResources

enum FontStyle: String, CaseIterable {
    case brockmanBold
    case brockmanMedium
    case brockmanRegular
    case brockmanSemibold
    case satoshiMedium

    func size(_ size: CGFloat) -> Font {
        font.font(size: size)
    }

    #if os(iOS)
    func uiFont(_ size: CGFloat) -> UIFont {
        font.uiFont(size: size)
    }
    #endif

    var fontName: String {
        font.postScriptName
    }

    private var font: VultisigFont {
        switch self {
        case .brockmanBold:
            .brockmannBold
        case .brockmanMedium:
            .brockmannMedium
        case .brockmanRegular:
            .brockmannRegular
        case .brockmanSemibold:
            .brockmannSemibold
        case .satoshiMedium:
            .satoshiMedium
        }
    }
}
