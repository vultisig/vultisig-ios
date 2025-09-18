//
//  HomeTab.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

enum HomeTab: TabBarItem, CaseIterable {
    case wallet
    case earn
    // Only used to fake `camera` button for liquid glass
    case camera
    
    var name: String {
        switch self {
        case .wallet:
            "Wallet"
        case .earn:
            "Earn"
        case .camera:
            ""
        }
    }
    
    var icon: String {
        switch self {
        case .wallet:
            "wallet"
        case .earn:
            "coins-add"
        case .camera:
            "camera-2"
        }
    }
}
