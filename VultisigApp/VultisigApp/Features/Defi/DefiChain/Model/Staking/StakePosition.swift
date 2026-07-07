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
    /// Contract address the position is staked into (e.g. a TON nominator
    /// pool). Drives the destination of an add-more / unstake transaction so
    /// those reuse the existing pool instead of re-prompting for it. `nil` for
    /// chains whose staking has no per-position pool address (THOR/Maya/Cosmos
    /// carry the destination elsewhere).
    var poolAddress: String?
    /// Pool implementation (`whales`, `tf`, …) for chains whose deposit/withdraw
    /// message is implementation-specific (TON nominator pools). Drives the
    /// add-more/unstake text comment so the right protocol token is sent.
    /// Optional so the lightweight SwiftData migration is safe; `nil` for chains
    /// that don't need it.
    var poolImplementation: String?
    /// Human-readable pool/delegator name (e.g. a TON nominator pool name) shown
    /// as the title on the staked card. Optional so the lightweight SwiftData
    /// migration is safe; `nil` for chains whose staking has no named pool.
    var poolName: String?
    /// When non-nil, a withdrawal is in progress (e.g. a TON nominator unstake
    /// was requested and the funds stay locked until the validation-cycle end at
    /// this Unix timestamp). Both staking and unstaking are gated while pending.
    /// Optional so the lightweight SwiftData migration is safe; `nil` for chains
    /// with no pending-withdrawal concept.
    var withdrawalUnlockTime: TimeInterval?

    // MARK: - Solana stake-account fields

    // Solana staking is per-STAKE-ACCOUNT (N rows per coin, on-chain-discovered),
    // unlike the one-row-per-coin THOR/Maya/TON staking this model otherwise
    // serves. These three optionals carry the per-account discriminator + the
    // bits needed to PAINT and IDENTIFY a Solana row before the live RPC refresh
    // lands. They are display/seed-only: the row's actions never sign from them —
    // a live `SolanaStakeAccount` from the refresh is required first. `nil` for
    // every non-Solana chain (lightweight SwiftData migration).

    /// Stake-account address — the per-account discriminator that makes the `id`
    /// unique across a vault's N Solana stake accounts. `nil` for non-Solana
    /// rows, which keeps their `id` byte-identical to the coin-keyed format.
    var stakeAccountPubkey: String?
    /// Vote account the stake delegates to — drives the seeded validator
    /// display. `nil` for non-Solana rows.
    var validatorVotePubkey: String?
    /// Raw value of `SolanaStakeActivationState` (activating/active/deactivating/
    /// inactive) — gates which row actions paint enabled while the seed shows.
    /// `nil` for non-Solana rows.
    var activationState: String?

    /// `false` while a withdrawal is pending (the deposit is locked); `true`
    /// otherwise, so chains without a pending-withdrawal concept are unaffected.
    var canStake: Bool {
        withdrawalUnlockTime == nil
    }

    var canUnstake: Bool {
        // A pending withdrawal locks the position: no second unstake until the
        // validation cycle ends.
        guard withdrawalUnlockTime == nil else { return false }
        let unstakeAmount = availableToUnstake ?? amount
        return !unstakeAmount.isZero && (unstakeMetadata?.canUnstake() ?? true)
    }

    var unstakeMessage: String? {
        if let unlockTime = withdrawalUnlockTime {
            let date = CustomDateFormatter.formatMonthDayYear(unlockTime)
            return String(format: "tonWithdrawalPendingMessage".localized, coin.ticker, date)
        }
        return unstakeMetadata?.unstakeMessage(for: coin)
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
        poolAddress: String? = nil,
        poolImplementation: String? = nil,
        poolName: String? = nil,
        withdrawalUnlockTime: TimeInterval? = nil,
        stakeAccountPubkey: String? = nil,
        validatorVotePubkey: String? = nil,
        activationState: String? = nil,
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
        self.poolAddress = poolAddress
        self.poolImplementation = poolImplementation
        self.poolName = poolName
        self.withdrawalUnlockTime = withdrawalUnlockTime
        self.stakeAccountPubkey = stakeAccountPubkey
        self.validatorVotePubkey = validatorVotePubkey
        self.activationState = activationState
        self.vault = vault
        self.id = StakePosition.makeID(coin: coin, vault: vault, stakeAccountPubkey: stakeAccountPubkey)
    }

    /// Builds the persistent `id`. The base is coin-keyed (one row per coin —
    /// the THOR/Maya/TON contract). Solana appends its stake-account pubkey so a
    /// vault's N stake accounts stay distinct; non-Solana rows pass `nil` and the
    /// `id` is byte-identical to the historical coin-keyed format (no migration).
    static func makeID(coin: CoinMeta, vault: Vault, stakeAccountPubkey: String?) -> String {
        let base = "\(coin.chain.ticker)_\(coin.contractAddress)_\(vault.pubKeyECDSA)"
        return base + (stakeAccountPubkey.map { "_\($0)" } ?? "")
    }

    convenience init(_ dto: StakePositionData, vault: Vault) {
        self.init(
            coin: dto.coin,
            type: dto.type,
            amount: dto.amount,
            availableToUnstake: dto.availableToUnstake,
            apr: dto.apr,
            estimatedReward: dto.estimatedReward,
            nextPayout: dto.nextPayout,
            rewards: dto.rewards,
            rewardCoin: dto.rewardCoin,
            unstakeMetadata: dto.unstakeMetadata,
            poolAddress: dto.poolAddress,
            poolImplementation: dto.poolImplementation,
            poolName: dto.poolName,
            withdrawalUnlockTime: dto.withdrawalUnlockTime,
            stakeAccountPubkey: dto.stakeAccountPubkey,
            validatorVotePubkey: dto.validatorVotePubkey,
            activationState: dto.activationState,
            vault: vault
        )
    }

    /// Updates everything except the lookup key (`coin`) and the persistent `id`.
    /// `stakeAccountPubkey` is only BACKFILLED when missing: rows written by an
    /// earlier build carry the pubkey in the `id` suffix but a nil field, which
    /// permanently broke the cache-first seed (`seedFromPersistedSnapshot`
    /// drops rows without a pubkey) because the id-keyed upsert always matched
    /// and this method never healed the field. The upsert matches by `id` and
    /// the `id` embeds the pubkey, so the DTO's value is by construction the
    /// same suffix — a non-nil field is never rewritten.
    func apply(_ dto: StakePositionData) {
        if stakeAccountPubkey?.isEmpty != false {
            stakeAccountPubkey = dto.stakeAccountPubkey
        }
        type = dto.type
        amount = dto.amount
        availableToUnstake = dto.availableToUnstake
        apr = dto.apr
        estimatedReward = dto.estimatedReward
        nextPayout = dto.nextPayout
        rewards = dto.rewards
        rewardCoin = dto.rewardCoin
        unstakeMetadata = dto.unstakeMetadata
        poolAddress = dto.poolAddress
        poolImplementation = dto.poolImplementation
        poolName = dto.poolName
        withdrawalUnlockTime = dto.withdrawalUnlockTime
        validatorVotePubkey = dto.validatorVotePubkey
        activationState = dto.activationState
    }
}

enum StakePositionType: String, Codable, Equatable {
    case stake
    case compound
    case index

    static func defaultType(for coin: CoinMeta) -> StakePositionType {
        switch coin.ticker.uppercased() {
        case "STCY":
            return .compound
        case "YRUNE", "YTCY":
            return .index
        default:
            return .stake
        }
    }
}
