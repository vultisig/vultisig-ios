import SwiftUI

struct ColorSystem: ColorSystemProtocol {
    var bgButtonPrimary: Color { .vultisig(hex: "33E6BF") }
    var bgButtonSecondary: Color { .vultisig(hex: "11284A") }
    var bgButtonTertiary: Color { .vultisig(hex: "2155DF") }

    // Hover in the design source.
    var bgButtonPrimaryPressed: Color { .vultisig(hex: "0FBF93") }
    var bgButtonSecondaryPressed: Color { .vultisig(hex: "0D1E38") }
    var bgButtonTertiaryPressed: Color { .vultisig(hex: "1E6AD1") }

    var bgButtonDisabled: Color { .vultisig(hex: "0B1A3A") }

    // Inset bevel for the 2026 button treatment.
    var buttonBevelLight: Color { .vultisig(hex: "FFFFFF").opacity(0.1) }
    var buttonBevelDark: Color { .vultisig(hex: "0F1C3E") }

    var textButtonDark: Color { .vultisig(hex: "02122B") }
    var textButtonLight: Color { .vultisig(hex: "F0F4FC") }
    var textButtonDisabled: Color { .vultisig(hex: "718096") }

    var bgPrimary: Color { .vultisig(hex: "02122B") }
    var bgSurface1: Color { .vultisig(hex: "061B3A") }
    var bgSurface2: Color { .vultisig(hex: "11284A") }
    var bgSurface12: Color { .vultisig(hex: "0D2240") }

    var lockPasscodeField: Color { .vultisig(hex: "1B3F73").opacity(0.1) }

    var bgSuccess: Color { .vultisig(hex: "042436") }
    var bgAlert: Color { .vultisig(hex: "362B17") }
    var bgError: Color { .vultisig(hex: "2B1111") }
    var bgNeutral: Color { .vultisig(hex: "061B3A") }
    var bgTooltip: Color { .vultisig(hex: "F5F5F5") }

    var primaryAccent1: Color { .vultisig(hex: "042D9A") }
    var primaryAccent2: Color { .vultisig(hex: "0439C7") }
    var primaryAccent3: Color { .vultisig(hex: "2155DF") }
    var primaryAccent4: Color { .vultisig(hex: "4879FD") }

    var textPrimary: Color { .vultisig(hex: "F0F4FC") }
    var textSecondary: Color { .vultisig(hex: "C9D6E8") }
    var textTertiary: Color { .vultisig(hex: "8295AE") }
    var textDark: Color { .vultisig(hex: "02122B") }

    var border: Color { .vultisig(hex: "11284A") }
    var borderLight: Color { .vultisig(hex: "11284A") }
    var borderExtraLight: Color { .vultisig(hex: "FFFFFF").opacity(0.03) }

    var alertSuccess: Color { .vultisig(hex: "13C89D") }
    var alertError: Color { .vultisig(hex: "FF5C5C") }
    var alertWarning: Color { .vultisig(hex: "FFC25C") }
    var alertInfo: Color { .vultisig(hex: "5CA7FF") }

    var turquoise: Color { .vultisig(hex: "33E6BF") }
    // Devices-selection blue glow used by onboarding and reshare.
    var devicesSelectionGlow: Color { .vultisig(hex: "084BFF") }

    // Promotional banner gradient endpoints from the 2026 banner system.
    var promoBannerBlue: Color { .vultisig(hex: "0348BB") }
    var promoBannerPurple: Color { .vultisig(hex: "A623EB") }
    var promoBannerIndigo: Color { .vultisig(hex: "1D0F88") }
    var promoBannerMutedPurple: Color { .vultisig(hex: "5C5277") }
    var promoBannerDeepBlue: Color { .vultisig(hex: "07156F") }
    var promoBannerBrightBlue: Color { .vultisig(hex: "0343CD") }

    // Chain-specific color.
    var tronRed: Color { .vultisig(hex: "FF0013") }
}

private extension Color {
    static func vultisig(hex: String) -> Color {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var integer: UInt64 = 0

        guard Scanner(string: value).scanHexInt64(&integer) else {
            return .clear
        }

        let alpha: UInt64
        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch value.count {
        case 3:
            (alpha, red, green, blue) = (
                255,
                (integer >> 8) * 17,
                (integer >> 4 & 0xF) * 17,
                (integer & 0xF) * 17
            )
        case 6:
            (alpha, red, green, blue) = (
                255,
                integer >> 16,
                integer >> 8 & 0xFF,
                integer & 0xFF
            )
        case 8:
            (alpha, red, green, blue) = (
                integer >> 24,
                integer >> 16 & 0xFF,
                integer >> 8 & 0xFF,
                integer & 0xFF
            )
        default:
            return .clear
        }

        return Color(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
