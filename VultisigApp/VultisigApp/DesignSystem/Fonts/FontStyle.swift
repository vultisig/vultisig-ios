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
        let customFont = UIFont(name: fontName, size: size)
        return Font(customFont ?? UIFont.systemFont(ofSize: size))
    }

    var fontName: String {
        "Brockmann-\(rawValue.capitalized)"
    }
}

extension UIFont {
    var font: Font {
        Font.custom(fontName, size: pointSize)
    }
}
