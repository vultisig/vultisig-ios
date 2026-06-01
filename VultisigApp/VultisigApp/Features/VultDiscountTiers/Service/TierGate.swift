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
    /// Prefers the cached balance path to avoid a network hit when the cache is
    /// warm. On a cache miss (e.g. cold start) it falls back to a real network
    /// fetch so entitled users aren't locked out until some unrelated flow
    /// populates the cache. Returns `false` only when the tier truly can't be
    /// resolved or is below the minimum.
    func isUnlocked(_ minimum: VultDiscountTier, for vault: Vault) async -> Bool {
        if let cached = await tierService.fetchDiscountTier(for: vault, cached: true) {
            return cached >= minimum
        }
        guard let fetched = await tierService.fetchDiscountTier(for: vault, cached: false) else {
            return false
        }
        return fetched >= minimum
    }
}
