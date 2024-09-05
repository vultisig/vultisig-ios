//
//  SetupVaultState.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI

enum SetupVaultState: CaseIterable {
    case TwoOfTwoVaults
    case TwoOfThreeVaults
    case MOfNVaults

    var title: String {
        switch self {
        case .TwoOfTwoVaults:
            return "FAST"
        case .TwoOfThreeVaults:
            return "ACTIVE"
        case .MOfNVaults:
            return "SECURE"
        }
    }

    var label: String {
        switch self {
        case .TwoOfTwoVaults:
            return """
            • Single Device Setup
            • Transaction Alerts & Policies
            • Vault Backup Emailed

            Use as a “hot vault”
            """
        case .TwoOfThreeVaults:
            return """
            • Fast Signing On The Move
            • Transaction Alerts & Policies
            • Fully self-custodial

            Use as a “main vault”
            """
        case .MOfNVaults:
            return """
            • Only Your Devices
            • No Alerts or Policies
            • Fully self-custodial

            Use as a “cold vault”
            """
        }
    }
    
    var image: String {
        switch self {
        case .TwoOfTwoVaults:
            return "SetupVaultImage1"
        case .TwoOfThreeVaults:
            return "SetupVaultImage2"
        case .MOfNVaults:
            return "SetupVaultImage3"
        }
    }
    
    var loaderTitle: String {
        // TODO: Change loader titles
        switch self {
        case .TwoOfTwoVaults:
            return NSLocalizedString("lookingFor1MoreDevice", comment: "")
        case .TwoOfThreeVaults:
            return NSLocalizedString("lookingFor2MoreDevice", comment: "")
        case .MOfNVaults:
            return NSLocalizedString("lookingForDevices", comment: "")
        }
    }
}
