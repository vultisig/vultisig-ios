//
//  DefaultColorSystem.swift
//  DesignSystem
//
//  Created by Gaston Mazzeo on 01/08/2025.
//

import SwiftUI

struct ColorSystem: ColorSystemProtocol {
    var bgButtonPrimary: Color { .init(hex: "33E6BF") }
    var bgButtonSecondary: Color { .init(hex: "061B3A") }
    var bgButtonTertiary: Color { .init(hex: "2155DF") }

    // Hover on Figma
    var bgButtonPrimaryPressed: Color { .init(hex: "0FBF93") }
    var bgButtonSecondaryPressed: Color { .init(hex: "0E2A41") }
    var bgButtonTertiaryPressed: Color { .init(hex: "1E6AD1") }

    var bgButtonDisabled: Color { .init(hex: "0B1A3A") }

    var textButtonDark: Color { .init(hex: "02122B") }
    var textButtonLight: Color { .init(hex: "F0F4FC") }
    var textButtonDisabled: Color { .init(hex: "718096") }

    var bgPrimary: Color { .init(hex: "02122B") }
    var bgSurface1: Color { .init(hex: "061B3A") }
    var bgSurface2: Color { .init(hex: "11284A") }

    var bgSuccess: Color { .init(hex: "042436") }
    var bgAlert: Color { .init(hex: "362B17") }
    var bgError: Color { .init(hex: "2B1111") }
    var bgNeutral: Color { .init(hex: "061B3A") }

    var primaryAccent1: Color { .init(hex: "042D9A") }
    var primaryAccent2: Color { .init(hex: "0439C7") }
    var primaryAccent3: Color { .init(hex: "2155DF") }
    var primaryAccent4: Color { .init(hex: "4879FD") }

    var textPrimary: Color { .init(hex: "F0F4FC") }
    var textSecondary: Color { .init(hex: "C9D6E8") }
    var textTertiary: Color { .init(hex: "8295AE") }
    var textDark: Color { .init(hex: "02122B") }

    var border: Color { .init(hex: "1B3F73") }
    var borderLight: Color { .init(hex: "11284A") }
    var borderExtraLight: Color { .init(hex: "FFFFFF").opacity(0.2) }

    var alertSuccess: Color { .init(hex: "13C89D") }
    var alertError: Color { .init(hex: "FF5C5C") }
    var alertWarning: Color { .init(hex: "FFC25C") }
    var alertInfo: Color { .init(hex: "5CA7FF") }

    var turquoise: Color { .init(hex: "33E6BF") }
}
