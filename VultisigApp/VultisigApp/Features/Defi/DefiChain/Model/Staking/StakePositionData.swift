//
//  StakePositionData.swift
//  VultisigApp
//
//  Sendable value-type DTO mirror of `StakePosition` (`@Model`).
//  Interactors return arrays of these so they don't construct `@Model` instances
//  off-MainActor (which would mutate `vault.stakePositions` via the inverse
//  relationship as a side effect of init). Storage materialization happens in
//  `DefiPositionsStorageService.upsert(stake:for:)`.
//

import Foundation

struct StakePositionData: Sendable, Equatable {
    let coin: CoinMeta
    let type: StakePositionType
    let amount: Decimal
    let availableToUnstake: Decimal?
    let apr: Double?
    let estimatedReward: Decimal?
    let nextPayout: TimeInterval?
    let rewards: Decimal?
    let rewardCoin: CoinMeta?
    let unstakeMetadata: UnstakeMetadata?
    /// `true` when the position came from a successful network fetch and should be persisted.
    /// `false` for fallback values built from cached metadata after an API failure — those
    /// must not overwrite the persisted record with stale data.
    let shouldPersist: Bool

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
        shouldPersist: Bool = true
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
        self.shouldPersist = shouldPersist
    }

    func id(for vault: Vault) -> String {
        "\(coin.chain.ticker)_\(coin.contractAddress)_\(vault.pubKeyECDSA)"
    }
}
