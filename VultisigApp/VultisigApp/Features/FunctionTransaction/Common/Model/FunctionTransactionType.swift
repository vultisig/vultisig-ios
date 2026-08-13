//
//  FunctionTransactionType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation

enum FunctionTransactionType: Hashable {
    case bond(coin: CoinMeta, node: String?)
    case unbond(node: BondNode)
    case stake(coin: CoinMeta, isAutocompound: Bool)
    case unstake(coin: CoinMeta, isAutocompound: Bool, availableToUnstake: Decimal? = nil)
    case withdrawRewards(coin: CoinMeta, rewards: Decimal, rewardsCoin: CoinMeta)
    case mint(coin: CoinMeta, yCoin: CoinMeta)
    case redeem(coin: CoinMeta, yCoin: CoinMeta)
    case addLP(position: LPPosition)
    case removeLP(position: LPPosition)
    case cosmosDelegate(coin: CoinMeta)
    case cosmosUndelegate(coin: CoinMeta, validatorAddress: String, validatorMoniker: String, stakedAmount: Decimal)
    case cosmosRedelegate(coin: CoinMeta, validatorAddress: String, validatorMoniker: String, stakedAmount: Decimal)
    case cosmosWithdrawRewards(coin: CoinMeta, validators: [CosmosWithdrawRewardsCandidate])
    /// Solana native-staking delegate (stake). The user picks a validator vote
    /// account and amount; the app builds + signs a create-and-delegate tx.
    ///
    /// Note: Solana unstake/withdraw are NOT routed here — they have no editable
    /// field, so `DefiChainMainScreen` builds the tx and pushes straight to
    /// Verify, skipping the confirm screen. A THORChain limit-order CANCEL
    /// follows the same pattern from `TransactionHistoryScreen`: it is
    /// deep-linked from the order card with its assets, amounts and memo already
    /// fixed, so it has nothing to confirm that Verify cannot say better.
    case solanaDelegate(coin: CoinMeta)
    /// TON nominator-pool stake. `poolAddress`/`poolImplementation` are the
    /// existing pool for add-more, or `nil` for a first-time stake (the picker
    /// supplies the pool, whose implementation resolves the deposit comment).
    case tonStake(coin: CoinMeta, poolAddress: String?, poolImplementation: String?)
    /// TON nominator-pool unstake (full withdrawal). `poolAddress` is the
    /// existing pool the position is staked into; `poolImplementation` resolves
    /// the withdraw comment; `stakedAmount` is shown for confirmation.
    case tonUnstake(coin: CoinMeta, poolAddress: String, poolImplementation: String?, stakedAmount: Decimal)
    /// THORChain / MayaChain node LEAVE. `node` is the validator address the
    /// memo names; it is optional so a caller that already knows it (a bond
    /// position card) can pre-fill the field, exactly as `.bond(coin:node:)`
    /// does, while a caller that does not leaves the user to type it.
    case leave(coin: CoinMeta, node: String?)
    /// Cosmos Hub → THORChain SWITCH. `coin` is the source chain's native
    /// asset: the transfer goes to THORChain's inbound vault for that chain,
    /// and that vault only credits the native asset — a Gaia IBC token sent
    /// there is simply lost. The destination is deliberately absent from the
    /// intent; it is the live inbound vault address, resolved when the
    /// transaction is built rather than carried from wherever the caller came
    /// from. The THORChain address the memo names comes from the vault, so it
    /// is not on the intent either.
    case theSwitch(coin: CoinMeta)
    var coins: [CoinMeta] {
        switch self {
        case .bond(let coin, _):
            return [coin]
        case .unbond(let node):
            return [node.coin]
        case .stake(let coin, _):
            return [coin]
        case .unstake(let coin, _, _):
            return [coin]
        case .withdrawRewards(let coin, _, let rewardsCoin):
            return [coin, rewardsCoin]
        case .mint(let coin, let yCoin):
            return [coin, yCoin]
        case .redeem(let coin, let yCoin):
            return [coin, yCoin]
        case .addLP(let position):
            return [position.coin1, position.coin2]
        case .removeLP(let position):
            return [position.coin1, position.coin2]
        case .cosmosDelegate(let coin):
            return [coin]
        case .cosmosUndelegate(let coin, _, _, _):
            return [coin]
        case .cosmosRedelegate(let coin, _, _, _):
            return [coin]
        case .cosmosWithdrawRewards(let coin, _):
            return [coin]
        case .solanaDelegate(let coin):
            return [coin]
        case .tonStake(let coin, _, _):
            return [coin]
        case .tonUnstake(let coin, _, _, _):
            return [coin]
        case .leave(let coin, _):
            return [coin]
        case .theSwitch(let coin):
            return [coin]
        }
    }
}

/// Sendable, Hashable value-type describing a single validator the user
/// has pending rewards with. Carried through the `FunctionTransactionType`
/// enum into the `CosmosWithdrawRewardsTransactionViewModel` so the
/// claim sheet can render the per-validator checklist without re-querying
/// the LCD.
struct CosmosWithdrawRewardsCandidate: Hashable, Sendable {
    let validatorAddress: String
    let validatorMoniker: String
    /// Pending reward amount in the chain's bond denom, human-decimal.
    let pendingReward: Decimal
}
