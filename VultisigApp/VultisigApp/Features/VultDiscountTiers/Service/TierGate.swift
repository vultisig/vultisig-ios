//
//  TierGate.swift
//  VultisigApp
//

import Foundation

/// Shared gate for VULT-tier-locked features.
///
/// Resolves a vault's discount tier and compares it against a required minimum
/// using `VultDiscountTier: Comparable`. Built here so other tier-gated features
/// (e.g. swap provider selection) can reuse the exact same unlock logic instead
/// of re-deriving it.
struct TierGate {

    private let tierService: VultTierService

    init(tierService: VultTierService = VultTierService()) {
        self.tierService = tierService
    }

    /// Returns `true` when `vault`'s tier is at least `minimum`.
    ///
    /// Uses the cached balance path to avoid a network hit when a gate is
    /// evaluated on screen open. Returns `false` when the tier can't be resolved
    /// (nil) or is below the minimum.
    func isUnlocked(_ minimum: VultDiscountTier, for vault: Vault) async -> Bool {
        guard let tier = await tierService.fetchDiscountTier(for: vault, cached: true) else {
            return false
        }
        return tier >= minimum
    }
}
