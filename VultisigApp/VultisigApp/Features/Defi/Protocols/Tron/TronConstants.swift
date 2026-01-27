//
//  TronConstants.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import Foundation
import SwiftUI

struct TronConstants {

    struct Design {
        static let horizontalPadding: CGFloat = 20
        static let cardPadding: CGFloat = 24
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
