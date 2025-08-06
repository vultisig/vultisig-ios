//
//  FontStyle.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

public enum FontStyle: String, CaseIterable {
    case bold
    case medium
    case regular
    case semibold

    public func size(_ size: CGFloat) -> Font {
        return Font.custom(fontName, size: size)
    }

    var fontName: String {
        "Brockmann-\(rawValue.capitalized)"
    }
}
