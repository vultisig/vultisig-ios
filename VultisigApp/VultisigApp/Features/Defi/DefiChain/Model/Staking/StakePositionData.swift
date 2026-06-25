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
    let poolAddress: String?
    /// Pool implementation (`whales`, `tf`, …) for chains whose deposit/withdraw
    /// message is implementation-specific (TON nominator pools). Resolves the
    /// add-more/unstake comment without re-fetching pool metadata. `nil` for
    /// chains that don't need it.
    let poolImplementation: String?

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
        poolAddress: String? = nil,
        poolImplementation: String? = nil
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
        self.poolAddress = poolAddress
        self.poolImplementation = poolImplementation
    }
}
