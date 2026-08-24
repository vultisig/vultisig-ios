//
//  VaultBannerType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/10/2025.
//

import Foundation
import SwiftUI

enum VaultBannerType: String, CarouselBannerType, CaseIterable {
    /// Declaration order is the carousel's order: `setupBanners` filters
    /// `allCases` and keeps this sequence, so `kaminoEarn` leading is what puts
    /// it on the first page. Nothing else depends on it — `rawValue` is the case
    /// name and `dismissalID` is spelled out separately, so moving a case can
    /// neither rename a banner nor invalidate a stored dismissal.
    case kaminoEarn, upgradeVault, backupVault, buyVult, followVultisig

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
        case .kaminoEarn:
            return "kamino_earn_solana"
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
        case .upgradeVault, .followVultisig, .kaminoEarn:
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
        case .kaminoEarn:
            "kaminoBannerTitle".localized
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
        case .kaminoEarn:
            "kaminoBannerSubtitle".localized
        }
    }

    var icon: ImageResource {
        switch self {
        case .upgradeVault:
            .circleArrowUp
        case .backupVault:
            .cloudUpload
        case .buyVult:
            .logoOutline
        case .followVultisig:
            .iconX
        case .kaminoEarn:
            .circleDollar
        }
    }

    var iconColor: Color {
        switch self {
        case .upgradeVault, .kaminoEarn:
            Theme.colors.alertInfo
        case .backupVault, .buyVult, .followVultisig:
            Theme.colors.textPrimary
        }
    }
}

/// Per-banner rule governing how long a dismissal suppresses a promo banner.
enum BannerDismissalRule: Equatable {
    /// Suppressed forever on this device. Backed by the same persistent,
    /// app-wide record as TTL dismissals, but the stored timestamp is treated
    /// only as evidence that the banner was dismissed and never expires.
    case permanent
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
