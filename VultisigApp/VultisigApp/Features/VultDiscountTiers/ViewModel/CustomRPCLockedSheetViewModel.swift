//
//  CustomRPCLockedSheetViewModel.swift
//  VultisigApp
//

import Foundation
import SwiftUI

/// Drives the Custom RPCs locked feature sheet: resolves the live $VULT balance
/// for the vault and exposes whether it clears the required tier threshold.
///
/// The required tier, its threshold amount, and the balance comparison are all
/// sourced from the existing tier system (`VultDiscountTier` / `VultTierService`)
/// — never from the design mock.
@MainActor
final class CustomRPCLockedSheetViewModel: ObservableObject {
    /// The minimum tier the locked feature requires. Sourced from the gate, not
    /// the design mock.
    let requiredTier: VultDiscountTier

    /// Live $VULT balance held by the vault, refreshed on appear.
    @Published private(set) var balance: Decimal = 0

    private let service: VultTierService

    init(requiredTier: VultDiscountTier, service: VultTierService = VultTierService()) {
        self.requiredTier = requiredTier
        self.service = service
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

    func loadBalance(for vault: Vault) async {
        balance = service.getVultToken(for: vault)?.balanceDecimal ?? 0
        _ = await service.fetchDiscountTier(for: vault, cached: false)
        balance = service.getVultToken(for: vault)?.balanceDecimal ?? 0
    }
}
