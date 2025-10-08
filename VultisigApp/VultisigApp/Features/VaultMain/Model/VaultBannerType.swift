//
//  VaultBannerType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import Foundation

enum VaultBannerType: String, CarouselBannerType, CaseIterable {
    case upgradeVault, backupVault, followVultisig
    
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .upgradeVault:
            "signFasterThanEverBefore".localized
        case .backupVault:
            "backupYourVaultNow".localized
        case .followVultisig:
            "followVultisigBannerTitle".localized
        }
    }
    var subtitle: String {
        switch self {
        case .upgradeVault:
            "upgradeYourVaultNow".localized
        case .backupVault:
            ""
        case .followVultisig:
            "followVultisigBannerSubtitle".localized
        }
    }
    var buttonTitle: String {
        switch self {
        case .upgradeVault:
            "upgradeNow".localized
        case .backupVault:
            "backupNow".localized
        case .followVultisig:
            "followVultisigBannerButtonTitle".localized
        }
    }
}
