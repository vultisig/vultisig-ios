//
//  SolanaStakingCooldownEstimate.swift
//  VultisigApp
//
//  Human-readable estimate for the deactivation cooldown. A Solana epoch is
//  ~2 days on mainnet (432,000 slots at ~400ms/slot), so a ~1-epoch cooldown
//  is surfaced as "~2 days". Kept as a single helper so the unstake screen and
//  any future copy share one definition rather than hardcoding the number.
//

import Foundation

enum SolanaStakingCooldownEstimate {
    /// Approximate mainnet epoch length in days. Informational copy only — the
    /// authoritative withdraw gate is `SolanaEpochCooldownGate`, which uses the
    /// live epoch, not this estimate.
    static let approximateDaysPerEpoch = 2

    /// Approximate calendar days for `epochs` epochs of cooldown.
    static func approximateDays(epochs: Int) -> Int {
        max(0, epochs) * approximateDaysPerEpoch
    }
}
