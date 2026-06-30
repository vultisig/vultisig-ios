//
//  VaultBannerType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import Foundation
import SwiftUI

enum VaultBannerType: String, CarouselBannerType, CaseIterable {
    case upgradeVault, backupVault, buyVult, followVultisig

    var id: String {
        rawValue
    }

    /// Stable, storage-facing identifier for this banner's dismissal intent.
    /// Decoupled from `rawValue` so renaming a case never invalidates a
    /// persisted dismissal.
    var dismissalID: String {
        switch self {
        case .backupVault:
            return "backup_vault_share"
        case .upgradeVault:
            return "upgrade_vault_dkls"
        case .buyVult:
            return "buy_vult_swap"
        case .followVultisig:
            return "follow_x_vultisig"
        }
    }

    /// How long a dismissal of this banner is honored. `buyVult` resurfaces a
    /// week later; `upgradeVault`/`followVultisig` a fortnight later; the
    /// backup reminder is session-scoped and reappears each cold launch while
    /// the vault is still un-backed-up.
    var dismissalRule: BannerDismissalRule {
        switch self {
        case .buyVult:
            return .ttl(.days(7))
        case .backupVault:
            return .session
        case .upgradeVault, .followVultisig:
            return .ttl(.days(15))
        }
    }

    var title: String {
        switch self {
        case .upgradeVault:
            "signFasterThanEverBefore".localized
        case .backupVault:
            "backupBannerTitle".localized
        case .buyVult:
            "buyVultBannerTitle".localized
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
        case .buyVult:
            "buyVultBannerSubtitle".localized
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
        case .buyVult:
            "buyVultBannerButtonTitle".localized
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
        case .buyVult:
            "buy-vult-banner-icon"
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
        case .buyVult:
            nil
        case .followVultisig:
            "follow-vultisig-banner-background"
        }
    }
}

/// Per-banner rule governing how long a dismissal suppresses a promo banner.
enum BannerDismissalRule: Equatable {
    /// Suppressed until `dismissedAt + interval`; reappears once the interval
    /// elapses. Backed by persistent (per-device) storage.
    case ttl(TimeInterval)
    /// Suppressed only for the current app session; reappears on the next cold
    /// launch. Never persisted.
    case session
}

extension TimeInterval {
    /// A whole number of days expressed as a `TimeInterval` (seconds).
    static func days(_ count: Int) -> TimeInterval {
        TimeInterval(count) * 24 * 60 * 60
    }
}
