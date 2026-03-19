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
    let stakedAmount: Decimal
    let apr: Double?
    let estimatedReward: Decimal?
    let nextPayoutDate: TimeInterval?
    let rewards: Decimal?
    let rewardsCoin: CoinMeta?

    static let empty = StakingDetails(
        stakedAmount: 0,
        apr: nil,
        estimatedReward: nil,
        nextPayoutDate: nil,
        rewards: nil,
        rewardsCoin: nil
    )
}
