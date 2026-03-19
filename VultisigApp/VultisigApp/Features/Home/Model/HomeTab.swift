//
//  HomeTab.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

enum HomeTab: TabBarItem, CaseIterable {
    case wallet
    case defi
    case agent
    // Only used to fake `camera` button for liquid glass
    case camera

    var name: String {
        switch self {
        case .wallet:
            "Wallet"
        case .defi:
            "DeFi"
        case .agent:
            "Agent"
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
        case .agent:
            "stars"
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
        case .agent:
            AccessibilityID.Home.agentTab
        case .camera:
            AccessibilityID.Home.cameraButton
        }
    }
}
