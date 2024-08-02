//
//  SetupVaultState.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI

enum SetupVaultState: String, CaseIterable {
    case TwoOfTwoVaults = "2 of 2"
    case TwoOfThreeVaults = "2 of 3"
    case MOfNVaults = "M of N"
    
    func getDescription() -> String {
        let title: String
        
        switch self {
        case .TwoOfTwoVaults:
            title = NSLocalizedString("youNeed1MoreDevice", comment: "")
        case .TwoOfThreeVaults:
            title = NSLocalizedString("youNeed2MoreDevice", comment: "")
        case .MOfNVaults:
            title = NSLocalizedString("youNeedNMoreDevice", comment: "")
        }
        
        return title
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
    
    func getNavigationTitle() -> String {
        switch self {
        case .TwoOfTwoVaults:
            return "2/2"
        case .TwoOfThreeVaults:
            return "2/3"
        case .MOfNVaults:
            return "M/N"
        }
    }
    
    func getLoaderTitle() -> String {
        let title: String
        
        switch self {
        case .TwoOfTwoVaults:
            title = NSLocalizedString("lookingFor1MoreDevice", comment: "")
        case .TwoOfThreeVaults:
            title = NSLocalizedString("lookingFor2MoreDevice", comment: "")
        case .MOfNVaults:
            title = NSLocalizedString("lookingForDevices", comment: "")
        }
        
        return title
    }
}
