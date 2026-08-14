//
//  FunctionTransactionType.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation

enum FunctionTransactionType: Hashable {
    case bond(coin: CoinMeta, node: String?)
    /// `node` is nil when the user is unbonding from a node the app never
    /// discovered a position for — the bond address is queried for active nodes,
    /// so a node that stopped reporting one would otherwise have no way out. The
    /// coin is carried separately because a nil node cannot supply it.
    case unbond(coin: CoinMeta, node: BondNode?)
    case stake(coin: CoinMeta, isAutocompound: Bool)
    case unstake(coin: CoinMeta, isAutocompound: Bool, availableToUnstake: Decimal? = nil)
    case withdrawRewards(coin: CoinMeta, rewards: Decimal, rewardsCoin: CoinMeta)
    case mint(coin: CoinMeta, yCoin: CoinMeta)
    case redeem(coin: CoinMeta, yCoin: CoinMeta)
    /// A deposit into an existing liquidity position.
    ///
    /// `side` names which of the position's two assets is deposited. It
    /// defaults to `.coin1` — the protocol's own asset, which is the only
    /// deposit the DeFi tab has ever made — so the existing callers are
    /// unchanged, while the L1 side is now expressible rather than assumed
    /// away.
    case addLP(position: LPPosition, side: LPDepositSide = .coin1)
    /// A THORChain liquidity deposit opened from a chain's action list, where
    /// no position exists yet: the user picks the pool, and the asset deposited
    /// follows that choice.
    case addThorchainLP(coin: CoinMeta)
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
    /// THORChain node REBOND. `node` pre-fills the node currently holding the
    /// bond when the caller already knows it, mirroring `.leave(coin:node:)`;
    /// the memo's second address and the optional partial amount are always
    /// typed on the form, so neither belongs on the intent.
    case rebond(coin: CoinMeta, node: String?)
    /// Rujira MERGE on THORChain. `coin` is the chain's native asset — the
    /// anchor and the fee asset — not the coin the transaction is built
    /// against: the form picks that from the merge catalog intersected with
    /// the vault's holdings, so every coin it can reach is already held.
    /// `denom` optionally names the catalog entry to open on, so a caller that
    /// already knows which token the user means (a position card) can
    /// pre-select it, exactly as `.leave(coin:node:)` pre-fills its address.
    case merge(coin: CoinMeta, denom: String?)
    /// THORChain RUJI UNMERGE — withdrawing merge shares back into the merged
    /// token. `coin` is THORChain's native asset: the merged tokens live inside
    /// the merge contract rather than the wallet, so the only coin this form
    /// needs the vault to resolve is the one that pays the fee. `denom` opens
    /// the picker on a token the caller already knows (`thor.kuji`, …); nil
    /// leaves it on the first offered one.
    case unmerge(coin: CoinMeta, denom: String?)
    /// THORChain secured-asset redemption (`SECURE-`). `coin` is THORChain's
    /// own native asset, deliberately *not* the asset being redeemed: which
    /// secured denoms a vault holds is a live bank-balance query, so no caller
    /// can name one upfront, and the native coin is the account those balances
    /// hang off. The form's picker resolves the redeemed coin from it.
    case withdrawSecuredAsset(coin: CoinMeta)
    var coins: [CoinMeta] {
        switch self {
        case .bond(let coin, _):
            return [coin]
        case .unbond(let coin, _):
            return [coin]
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
        case .addLP(let position, _):
            return [position.coin1, position.coin2]
        case .addThorchainLP(let coin):
            // The entry asset plus RUNE: a THORChain pool credits liquidity to
            // a RUNE account the memo has to name, so a vault without one
            // cannot make this deposit at all. Naming both here is what lets
            // the caller's `needsCoinAddition` / `addCoins` resolve them.
            //
            // The pool picker can reassign the deposited asset to another token
            // on the same chain, but only to one the vault already holds — the
            // list is built from its own coins — so nothing the picker reaches
            // needs adding.
            let rune = TokensStore.TokenSelectionAssets.first { $0.chain == .thorChain && $0.isNativeToken }
            return [coin] + (rune.map { [$0] } ?? [])
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
        case .rebond(let coin, _):
            return [coin]
        case .merge(let coin, _):
            return [coin]
        case .unmerge(let coin, _):
            return [coin]
        case .withdrawSecuredAsset(let coin):
            // Only the native coin: the secured assets themselves are added to
            // the vault by the form as it discovers which ones the account
            // actually holds, so they cannot be pre-resolved here.
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
