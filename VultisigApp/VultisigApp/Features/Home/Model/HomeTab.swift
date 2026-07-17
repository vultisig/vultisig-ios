//
//  HomeTab.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

enum HomeTab: TabBarItem, CaseIterable {
    case wallet
    case defi
    // Only used to fake `camera` button for liquid glass
    case camera

    var name: String {
        switch self {
        case .wallet:
            "Wallet"
        case .defi:
            "DeFi"
        case .camera:
            ""
        }
    }

    var icon: ImageResource {
        switch self {
        case .wallet:
            .wallet
        case .defi:
            .nodes
        case .camera:
            .camera2
        }
    }

    var accessibilityID: String? {
        switch self {
        case .wallet:
            AccessibilityID.Home.walletTab
        case .defi:
            AccessibilityID.Home.defiTab
        case .camera:
            AccessibilityID.Home.cameraButton
        }
    }
}
