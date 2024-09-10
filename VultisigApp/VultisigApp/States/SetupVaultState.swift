//
//  SetupVaultState.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI

enum SetupVaultState: CaseIterable {
    case fast
    case active
    case secure

    var isFastVault: Bool {
        switch self {
        case .fast, .active:
            return true
        case .secure:
            return false
        }
    }

    var title: String {
        switch self {
        case .fast:
            return "FAST"
        case .active:
            return "ACTIVE"
        case .secure:
            return "SECURE"
        }
    }

    var label: String {
        switch self {
        case .fast:
            return """
            • Single Device Setup
            • Transaction Alerts & Policies
            • Vault Backup Emailed

            Use as a “hot vault”
            """
        case .active:
            return """
            • Fast Signing On The Move
            • Transaction Alerts & Policies
            • Fully self-custodial

            Use as a “main vault”
            """
        case .secure:
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
        case .fast:
            return "SetupVaultImage1"
        case .active:
            return "SetupVaultImage2"
        case .secure:
            return "SetupVaultImage3"
        }
    }
    
    var loaderTitle: String {
        // TODO: Change loader titles
        switch self {
        case .fast:
            return NSLocalizedString("lookingFor1MoreDevice", comment: "")
        case .active:
            return NSLocalizedString("lookingFor2MoreDevice", comment: "")
        case .secure:
            return NSLocalizedString("lookingForDevices", comment: "")
        }
    }
}
