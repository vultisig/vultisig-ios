//
//  VaultBannerType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import Foundation
import SwiftUI

enum VaultBannerType: String, CarouselBannerType, CaseIterable {
    case upgradeVault, backupVault, followVultisig

    var id: String {
        rawValue
    }

    var isAppBanner: Bool {
        switch self {
        case .upgradeVault, .backupVault:
            return false
        case .followVultisig:
            return true
        }
    }

    var title: String {
        switch self {
        case .upgradeVault:
            "signFasterThanEverBefore".localized
        case .backupVault:
            "backupBannerTitle".localized
        case .followVultisig:
            "followVultisigBannerTitle".localized
        }
    }
    var subtitle: String {
        switch self {
        case .upgradeVault:
            "upgradeYourVaultNow".localized
        case .backupVault:
            "backupBannerSubtitle".localized
        case .followVultisig:
            "followVultisigBannerSubtitle".localized
        }
    }

    var buttonTitle: String {
        switch self {
        case .upgradeVault:
            "upgradeNow".localized
        case .backupVault:
            "backupBannerButtonTitle".localized
        case .followVultisig:
            "followVultisigBannerButtonTitle".localized
        }
    }

    var image: String {
        switch self {
        case .upgradeVault:
            "upgrade-vault-banner-icon"
        case .backupVault:
            "backup-vault-banner-icon"
        case .followVultisig:
            "follow-vultisig-banner-icon"
        }
    }

    var background: String? {
        switch self {
        case .upgradeVault:
            nil
        case .backupVault:
            "backup-vault-banner-background"
        case .followVultisig:
            "follow-vultisig-banner-background"
        }
    }
}
