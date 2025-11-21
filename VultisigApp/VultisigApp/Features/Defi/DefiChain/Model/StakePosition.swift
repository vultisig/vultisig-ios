//
//  StakePosition.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/10/2025.
//

import Foundation
import SwiftData

@Model
final class StakePosition {
    @Attribute(.unique) var id: String
    
    var coin: CoinMeta
    var type: StakePositionType
    var amount: Decimal
    var apr: Double?
    var estimatedReward: Decimal?
    var nextPayout: TimeInterval?
    var rewards: Decimal?
    var rewardCoin: CoinMeta?
    
    @Relationship(inverse: \Vault.stakePositions) var vault: Vault?
    
    init(
        coin: CoinMeta,
        type: StakePositionType,
        amount: Decimal,
        apr: Double? = nil,
        estimatedReward: Decimal? = nil,
        nextPayout: TimeInterval? = nil,
        rewards: Decimal? = nil,
        rewardCoin: CoinMeta? = nil,
        vault: Vault
    ) {
        self.coin = coin
        self.type = type
        self.amount = amount
        self.apr = apr
        self.estimatedReward = estimatedReward
        self.nextPayout = nextPayout
        self.rewards = rewards
        self.rewardCoin = rewardCoin
        self.vault = vault
        self.id = "\(coin.chain.ticker)_\(coin.contractAddress)_\(vault.pubKeyECDSA)"
    }
}

enum StakePositionType: String, Codable, Equatable {
    case stake
    case compound
    case index
}
