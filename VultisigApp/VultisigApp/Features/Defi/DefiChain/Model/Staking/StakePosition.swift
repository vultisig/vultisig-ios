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
    var availableToUnstake: Decimal?
    var apr: Double?
    var estimatedReward: Decimal?
    var nextPayout: TimeInterval?
    var rewards: Decimal?
    var rewardCoin: CoinMeta?
    var unstakeMetadata: UnstakeMetadata?

    var canUnstake: Bool {
        let unstakeAmount = availableToUnstake ?? amount
        return !unstakeAmount.isZero && (unstakeMetadata?.canUnstake ?? true)
    }

    var unstakeMessage: String? {
        unstakeMetadata?.unstakeMessage(for: coin)
    }

    @Relationship(inverse: \Vault.stakePositions) var vault: Vault?

    init(
        coin: CoinMeta,
        type: StakePositionType,
        amount: Decimal,
        availableToUnstake: Decimal? = nil,
        apr: Double? = nil,
        estimatedReward: Decimal? = nil,
        nextPayout: TimeInterval? = nil,
        rewards: Decimal? = nil,
        rewardCoin: CoinMeta? = nil,
        unstakeMetadata: UnstakeMetadata? = nil,
        vault: Vault
    ) {
        self.coin = coin
        self.type = type
        self.amount = amount
        self.availableToUnstake = availableToUnstake
        self.apr = apr
        self.estimatedReward = estimatedReward
        self.nextPayout = nextPayout
        self.rewards = rewards
        self.rewardCoin = rewardCoin
        self.unstakeMetadata = unstakeMetadata
        self.vault = vault
        self.id = "\(coin.chain.ticker)_\(coin.contractAddress)_\(vault.pubKeyECDSA)"
    }
}

enum StakePositionType: String, Codable, Equatable {
    case stake
    case compound
    case index
}
