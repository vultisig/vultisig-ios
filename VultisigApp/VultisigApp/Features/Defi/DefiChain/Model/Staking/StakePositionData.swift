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
    /// Human-readable pool/delegator name (e.g. a TON nominator pool name) shown
    /// on the staked card. `nil` for chains whose staking has no named pool.
    let poolName: String?
    /// `false` when staking more is currently blocked (e.g. a TON nominator
    /// withdrawal is pending, so the funds are locked until the validation cycle
    /// ends). Defaults to `true` so chains without a pending-withdrawal concept
    /// are unaffected.
    let canStake: Bool
    /// When non-nil, a withdrawal is in progress and BOTH stake and unstake are
    /// locked until this Unix timestamp (the pool's validation-cycle end). Drives
    /// the explanatory label on the staked card. `nil` for chains/positions with
    /// no pending withdrawal.
    let withdrawalUnlockTime: TimeInterval?
    /// Solana stake-account address — the per-account discriminator that makes a
    /// row's persistent `id` unique across a vault's N stake accounts. `nil` for
    /// non-Solana positions. See `StakePosition` for the full rationale.
    let stakeAccountPubkey: String?
    /// Solana vote account the stake delegates to. `nil` for non-Solana.
    let validatorVotePubkey: String?
    /// Raw value of `SolanaStakeActivationState`. `nil` for non-Solana.
    let activationState: String?

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
        poolImplementation: String? = nil,
        poolName: String? = nil,
        canStake: Bool = true,
        withdrawalUnlockTime: TimeInterval? = nil,
        stakeAccountPubkey: String? = nil,
        validatorVotePubkey: String? = nil,
        activationState: String? = nil
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
        self.poolName = poolName
        self.canStake = canStake
        self.withdrawalUnlockTime = withdrawalUnlockTime
        self.stakeAccountPubkey = stakeAccountPubkey
        self.validatorVotePubkey = validatorVotePubkey
        self.activationState = activationState
    }
}
