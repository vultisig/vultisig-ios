//
//  StakePosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import Foundation

struct StakePosition: Identifiable, Equatable {
    var id: String { coin.ticker + coin.contractAddress }
    
    let coin: CoinMeta
    let type: StakePositionType
    let amount: Decimal
    let apr: Double?
    let estimatedReward: Decimal?
    let nextPayout: TimeInterval?
    let rewards: Decimal?
    let rewardCoin: CoinMeta?
}

enum StakePositionType: Equatable {
    case stake
    case compound
    case index
}
