//
//  Color.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

extension Color {
    init(hex: String) {
        self.init(light: hex, dark: nil)
    }

    init(light: String, dark: String?) {
        let lightColor = PlatformColor(hex: light) ?? .clear
        let darkColor = PlatformColor(hex: dark ?? light) ?? .clear
        self.init(light: lightColor, dark: darkColor)
    }

    init(light: PlatformColor, dark: PlatformColor?) {
        self.init(.dynamic(light: light, dark: dark ?? light))
    }

    var toCGColor: CGColor {
        #if canImport(UIKit)
        UIColor(self).cgColor
        #elseif canImport(AppKit)
        NSColor(self).cgColor
        #endif
    }
}

extension PlatformColor {
    private static var hexColorCache = [String: CGColor]()

    static func dynamic(light: PlatformColor?, dark: PlatformColor?) -> PlatformColor {
#if canImport(UIKit)
        return PlatformColor { trait in
            switch trait.userInterfaceStyle {
            case .dark:
                return dark ?? clear
            case .light, .unspecified:
                return light ?? clear
            @unknown default:
                return light ?? clear
            }
        }
#elseif canImport(AppKit)
        return PlatformColor(name: nil) { appearance in
            let appearanceName = appearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
            switch appearanceName {
            case .darkAqua:
                return dark ?? .clear
            default:
                return light ?? .clear
            }
        }
#endif
    }

    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        // Return nil for empty strings
        guard !hex.isEmpty else { return nil }

        if let cachedColor = Self.hexColorCache[hex] {
            self.init(cgColor: cachedColor)
            return
        }

        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            // Invalid hex format - return nil instead of creating invalid color
            return nil
        }

        defer { Self.hexColorCache[hex] = self.cgColor }

        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}
