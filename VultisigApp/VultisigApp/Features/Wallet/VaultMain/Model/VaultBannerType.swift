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
    case kaminoEarn
    case upgradeVault
    case rujiraStaking
    case followVultisig
    case backupVault
    case referralRewards
    case buyVult

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
        case .rujiraStaking:
            return "rujira_staking_thorchain"
        case .referralRewards:
            return "referral_rewards_code"
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
        case .upgradeVault, .followVultisig, .kaminoEarn, .rujiraStaking, .referralRewards:
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
        case .rujiraStaking:
            "rujiraBannerTitle".localized
        case .referralRewards:
            "referralRewardsBannerTitle".localized
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
        case .rujiraStaking:
            "rujiraBannerSubtitle".localized
        case .referralRewards:
            "referralRewardsBannerSubtitle".localized
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
        case .rujiraStaking:
            .ruji
        case .referralRewards:
            .stars
        }
    }

    var iconColor: Color? {
        switch self {
        case .upgradeVault, .kaminoEarn:
            Theme.colors.alertInfo
        case .backupVault, .buyVult, .followVultisig:
            Theme.colors.textPrimary
        case .rujiraStaking, .referralRewards:
            nil
        }
    }

    var artwork: ImageResource {
        switch self {
        case .upgradeVault:
            .bannerUpgrade
        case .rujiraStaking:
            .bannerRujira
        case .followVultisig:
            .bannerFollowX
        case .backupVault:
            .bannerBackup
        case .referralRewards:
            .bannerReferral
        case .buyVult:
            .bannerBuyVult
        case .kaminoEarn:
            .bannerKamino
        }
    }

    var artworkSize: CGFloat {
        self == .buyVult ? 112 : 125
    }

    var gradientEndColor: Color {
        switch self {
        case .upgradeVault:
            Theme.colors.promoBannerBlue
        case .rujiraStaking:
            Theme.colors.promoBannerPurple
        case .followVultisig:
            Theme.colors.promoBannerIndigo
        case .backupVault:
            Theme.colors.promoBannerMutedPurple
        case .referralRewards, .kaminoEarn:
            Theme.colors.promoBannerDeepBlue
        case .buyVult:
            Theme.colors.promoBannerBrightBlue
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
