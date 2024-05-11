//
//  SetupVaultState.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI

enum SetupVaultState: String, CaseIterable {
    case TwoOfTwoVaults = "2Of2Vault"
    case TwoOfThreeVaults = "2Of3Vault"
    case MOfNVaults = "MOfNVault"
    
    func getDescription() -> String {
        getTitle() + getFirstDescription() + getSecondDescription()
    }
    
    func getImage() -> String {
        let image: String
        
        switch self {
        case .TwoOfTwoVaults:
            image = "SetupVaultImage1"
        case .TwoOfThreeVaults:
            image = "SetupVaultImage2"
        case .MOfNVaults:
            image = "SetupVaultImage3"
        }
        return image
    }
    
    private func getTitle() -> String {
        let title: String
        
        switch self {
        case .TwoOfTwoVaults:
            title = NSLocalizedString("youNeedAtLeast", comment: "") + " 2 " + NSLocalizedString("devices", comment: "")
        case .TwoOfThreeVaults:
            title = NSLocalizedString("youNeedAtLeast", comment: "") + " 3 " + NSLocalizedString("devices", comment: "")
        case .MOfNVaults:
            title = NSLocalizedString("MOfNVault", comment: "")
        }
        
        return title + "\n"
    }
    
    private func getFirstDescription() -> String {
        "1. " + NSLocalizedString("startFromOneDevice", comment: "") + "\n"
    }
    
    private func getSecondDescription() -> String {
        let description: String
        
        switch self {
        case .TwoOfTwoVaults:
            description = NSLocalizedString("second", comment: "")
        case .TwoOfThreeVaults:
            description = NSLocalizedString("secondAndThird", comment: "")
        case .MOfNVaults:
            description = NSLocalizedString("other", comment: "")
        }
        
        return "2. " + NSLocalizedString("pairFromThe", comment: "") + " \(description) " + NSLocalizedString("device", comment: "")
    }
}
