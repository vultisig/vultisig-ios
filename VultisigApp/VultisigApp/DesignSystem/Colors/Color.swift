//
//  Color.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

public extension Color {
    init(hex: String) {
        self.init(light: hex, dark: nil)
    }

    init(light: String, dark: String?) {
        let lightColor = UIColor(hex: light)
        let darkColor = UIColor(hex: dark ?? light)
        self.init(light: lightColor, dark: darkColor)
    }

    init(light: UIColor, dark: UIColor?) {
        self.init(.dynamic(light: light, dark: dark ?? light))
    }
}


extension UIColor {
    private static var hexColorCache = [String: CGColor]()

    static func dynamic(light: UIColor?, dark: UIColor?) -> UIColor {
        return UIColor { trait in
            switch trait.userInterfaceStyle {
            case .dark:
                return dark ?? clear
            case .light, .unspecified:
                return light ?? clear
            @unknown default:
                return light ?? clear
            }
        }
    }

    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        if let cachedColor = Self.hexColorCache[hex] {
            self.init(cgColor: cachedColor)
            return
        }


        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        defer { Self.hexColorCache[hex] = self.cgColor }

        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}
