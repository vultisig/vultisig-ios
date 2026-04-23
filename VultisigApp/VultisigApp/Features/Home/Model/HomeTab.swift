//
//  HomeTab.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

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

    var icon: String {
        switch self {
        case .wallet:
            "wallet"
        case .defi:
            "coins-add"
        case .camera:
            "camera-2"
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
