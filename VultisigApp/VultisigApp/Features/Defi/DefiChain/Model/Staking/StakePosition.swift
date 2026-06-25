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
        self.vault = vault
        self.id = "\(coin.chain.ticker)_\(coin.contractAddress)_\(vault.pubKeyECDSA)"
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
            vault: vault
        )
    }

    /// Updates everything except the lookup key (`coin`) and the persistent `id`.
    func apply(_ dto: StakePositionData) {
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
