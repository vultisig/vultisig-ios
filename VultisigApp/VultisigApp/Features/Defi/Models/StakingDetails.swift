//
//  StakingDetails.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/10/2025.
//

import Foundation

/// Internal data structure for staking service responses
/// This model is used by THORChainStakingService to return staking information
/// Can be easily converted to StakePosition for the view layer
struct StakingDetails {
    /// Amount held in the plain (non auto-compounding) position. For RUJI this is
    /// the bonded position — the one that accrues manually-claimable USDC.
    let stakedAmount: Decimal
    /// Amount held in the auto-compounding position, denominated in the bond
    /// token (not in receipt shares). `0` for coins whose staking has no
    /// auto-compounding side reported by the same API call.
    let autoCompoundAmount: Decimal
    let apr: Double?
    let estimatedReward: Decimal?
    let nextPayoutDate: TimeInterval?
    let rewards: Decimal?
    let rewardsCoin: CoinMeta?

    static let empty = StakingDetails(
        stakedAmount: 0,
        autoCompoundAmount: 0,
        apr: nil,
        estimatedReward: nil,
        nextPayoutDate: nil,
        rewards: nil,
        rewardsCoin: nil
    )
}
