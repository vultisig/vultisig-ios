//
//  FunctionTransactionKind.swift
//  VultisigApp
//
//  What a function transaction IS, in one word, for the screens that have to
//  announce it before it is signed.
//
//  ⚠️ **The verb and the amount are separate problems, and conflating them is
//  what kept this from generalising.** `withdrawDisplayAmount` answers "what
//  figure, when `amount` cannot say" — a memo-only `MsgDeposit` carries a literal
//  `"0"`, so the figure has to travel out of band. That is a real problem, but it
//  is only TCY's and CACAO's. Every other DeFi operation has a perfectly good
//  `amount` and needs nothing but the right word: a Cosmos delegate, a bond, an
//  addLP were all announced as "You're sending" purely because the only trigger on
//  offer was an *amount* field they had no reason to set.
//
//  So the verb gets its own carrier. A builder opts in by naming its kind; the
//  amount keeps whatever answer it already had.
//

import Foundation

/// The operation a `TransactionBuilder` performs, when it is one the generic send
/// vocabulary describes wrongly.
///
/// One verb per operation, not per asset: a TCY stake, a RUJI stake and a TON
/// pool deposit are all "staking", and giving each its own copy would be twelve
/// more strings saying the same thing in eight locales apiece.
///
/// ⚠️ **Not every verb has a live producer today, and that is a recorded state
/// rather than an oversight.** The vocabulary is the specification; what is
/// missing is a figure or a route, not the word:
///
/// - `.claimRewards` — both claim builders name it, and both are suppressed: a
///   Cosmos `MsgWithdrawDelegatorReward` carries no Coin, and RUJI pays its
///   revenue in a different asset from the one the builder holds.
/// - `.undelegate` / `.redelegate` — only Cosmos builders carry them, and Cosmos
///   staking is verified on `CosmosStakingVerifySummaryView`, which renders its
///   own headline and never asks the resolver.
/// - `.removeLiquidity` — an LP withdrawal's `amount` is the attach dust, and the
///   liquidity itself is a share of a two-sided position that one coin cannot
///   state.
/// - `.mint` — the yVault deposit spends one coin and mints another; the hero
///   names one.
///
/// Each of those is a note on the builder that would use it. Deleting the cases
/// would only mean re-adding them the day the figure arrives.
enum FunctionTransactionKind: String, CaseIterable {
    case stake
    case unstake
    case bond
    case unbond
    case delegate
    case undelegate
    case redelegate
    case claimRewards
    case mint
    case redeem
    case addLiquidity
    case removeLiquidity

    /// The headline on the initiator's Verify screen, above the amount.
    ///
    /// `stake` / `unstake` reuse the keys the Cosmos staking verify screen
    /// already renders rather than adding a second pair with identical copy —
    /// they are the same sentence about the same kind of operation, and two keys
    /// would only let the two screens drift apart.
    var verifyTitle: String {
        switch self {
        case .stake: return "youreStaking".localized
        case .unstake: return "youreUnstaking".localized
        case .bond: return "youreBonding".localized
        case .unbond: return "youreUnbonding".localized
        case .delegate: return "youreDelegating".localized
        case .undelegate: return "youreUndelegating".localized
        case .redelegate: return "youreRedelegating".localized
        case .claimRewards: return "youreClaimingRewards".localized
        case .mint: return "youreMinting".localized
        case .redeem: return "youreRedeeming".localized
        case .addLiquidity: return "youreAddingLiquidity".localized
        case .removeLiquidity: return "youreRemovingLiquidity".localized
        }
    }
}
