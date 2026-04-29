//
//  PreviousStakeMetadata.swift
//  VultisigApp
//
//  Created by Claude on 28/04/2026.
//

import Foundation

/// Snapshot of metadata copied off a persisted StakePosition so it can be safely passed
/// across actor boundaries (StakePosition is a SwiftData @Model and is MainActor-bound).
/// Used by stake interactors to preserve APR / rewards / nextPayout when a detail-fetch
/// fails and they must construct a degraded fallback position.
struct PreviousStakeMetadata {
    let apr: Double?
    let estimatedReward: Decimal?
    let nextPayout: TimeInterval?
    let rewards: Decimal?
    let rewardCoin: CoinMeta?
}
