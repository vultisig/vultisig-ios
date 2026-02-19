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
}
