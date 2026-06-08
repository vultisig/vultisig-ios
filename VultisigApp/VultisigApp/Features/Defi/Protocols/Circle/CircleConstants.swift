//
//  CircleConstants.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/12/25.
//

import Foundation
import SwiftUI

struct CircleConstants {
    static let usdcMainnet = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    static let usdcSepolia = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"

    /// Circle deposits and new account onboarding are currently disabled.
    /// Existing account holders can still view their balance and withdraw funds.
    static let depositsEnabled = false

    struct Design {
        static let horizontalPadding: CGFloat = 20
        static let cardPadding: CGFloat = 16
        static let verticalSpacing: CGFloat = 16
        static let cornerRadius: CGFloat = 16

        #if os(macOS)
        static let mainViewTopPadding: CGFloat = 60
        #else
        static let mainViewTopPadding: CGFloat = 16
        #endif

        static let mainViewBottomPadding: CGFloat = 32
    }

    struct Fonts {
        static let title = Theme.fonts.bodyLMedium
        static let subtitle = Theme.fonts.caption12
        static let balance = Theme.fonts.priceTitle1
        static let body = Theme.fonts.bodySMedium
        static let headline = Theme.fonts.bodyLMedium
    }
}
