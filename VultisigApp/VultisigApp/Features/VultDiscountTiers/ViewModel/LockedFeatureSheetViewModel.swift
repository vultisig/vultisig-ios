//
//  LockedFeatureSheetViewModel.swift
//  VultisigApp
//

import Foundation

/// Drives the generic tier-locked feature sheet: resolves the live staked $VULT
/// balance for the vault and exposes whether it clears the feature's required
/// tier threshold.
///
/// The required tier, its threshold amount, and the balance comparison are all
/// sourced from the existing tier system (`VultDiscountTier` / `VultTierService`)
/// via the `LockedFeature` descriptor — never from the design mock. Tiers are
/// unlocked by staking, so the balance is the staked sVULT balance.
@MainActor
final class LockedFeatureSheetViewModel: ObservableObject {
    let feature: LockedFeature

    /// Live staked $VULT balance held by the vault, refreshed on appear.
    @Published private(set) var balance: Decimal = 0

    private let service: VultTierService

    init(feature: LockedFeature, service: VultTierService = VultTierService()) {
        self.feature = feature
        self.service = service
    }

    /// The minimum tier the locked feature requires.
    var requiredTier: VultDiscountTier {
        feature.requiredTier
    }

    /// The $VULT amount required to reach `requiredTier`, from the tier config.
    var threshold: Decimal {
        requiredTier.balanceToUnlock
    }

    /// `true` when the vault's balance is below the required tier threshold —
    /// drives the warning color on the balance row.
    var isBelowThreshold: Bool {
        Self.isBelow(balance: balance, threshold: threshold)
    }

    /// Pure threshold comparison: `true` when `balance` is strictly below
    /// `threshold`. Extracted so the warning-state logic is testable without a
    /// live balance fetch.
    static func isBelow(balance: Decimal, threshold: Decimal) -> Bool {
        balance < threshold
    }

    var thresholdText: String {
        "\(threshold.formatForDisplay(skipAbbreviation: true)) VULT"
    }

    var balanceText: String {
        "\(balance.formatForDisplay(skipAbbreviation: true)) VULT"
    }

    /// Reads the already-cached staked $VULT (sVULT) balance from the vault's
    /// token — no network refresh. The balance is kept current by the app's
    /// existing fetch paths.
    func loadBalance(for vault: Vault) {
        balance = service.getStakedVultToken(for: vault)?.balanceDecimal ?? 0
    }
}
