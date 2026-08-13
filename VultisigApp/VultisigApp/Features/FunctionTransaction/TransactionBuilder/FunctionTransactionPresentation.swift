//
//  FunctionTransactionPresentation.swift
//  VultisigApp
//
//  How a DeFi function transaction is presented on the screen where it is
//  approved.
//
//  Without it every one of them renders through the generic send vocabulary: a
//  Cosmos delegate, a THORChain bond, an addLP and a staked withdrawal all read
//  "You're sending", and the withdrawal reads "You're sending 0 TCY" over a
//  thousand of them because a memo-only `MsgDeposit` really does carry a zero
//  amount.
//
//  This replaced a presentation that existed for the withdrawal alone and keyed
//  off `withdrawDisplayAmount`. That trigger was an AMOUNT, so the only
//  operations that could reach it were the ones whose amount was unusable —
//  every operation that had a perfectly good amount and only needed the right
//  word was locked out by construction. The verb now has its own carrier
//  (`FunctionTransactionKind`) and the amount keeps the answer it already had.
//

import Foundation

enum FunctionTransactionPresentation {

    /// Hero for the initiator's Verify screen, or `nil` for a transaction that
    /// has not named itself (every other function call keeps its existing
    /// presentation).
    ///
    /// ⚠️ **A named operation with no figure gets NO hero, deliberately.** This
    /// is the guard that keeps the amount honest, and it is not hypothetical:
    /// several builders that legitimately carry the verb cannot state a figure in
    /// the transaction's own coin — an auto-compounding position redeems receipt
    /// shares worth more than one token each, a Cosmos rewards claim carries no
    /// Coin at all. Their `amount` is a placeholder, so announcing "You're
    /// unstaking 0 TCY" would be the same defect this screen exists to remove,
    /// wearing a better verb. Falling through to the generic header leaves them
    /// exactly as they are today, which is the honest outcome until a real figure
    /// exists to name.
    ///
    /// A builder whose `amount` is a non-zero CARRIER rather than the operation's
    /// figure — the 0.2 TON a nominator-pool withdrawal signals with, the 0.02
    /// RUNE an LP withdrawal attaches — is not saved by this guard and must not
    /// name a kind at all. Each such builder says so at its `functionKind`.
    static func hero(for transaction: SendTransaction) -> HeroContent? {
        guard let kind = transaction.functionKind else { return nil }

        // The builder's out-of-band figure when it has one, the transaction's own
        // amount otherwise. Most operations need only the second — the first
        // exists for the memo-only deposits whose `amount` is a literal "0".
        let amount = transaction.withdrawDisplayAmount ?? transaction.amountDecimal
        guard amount > 0 else { return nil }

        return .send(
            title: kind.verifyTitle,
            coin: HeroCoinAmount(
                // Rendered at the ASSET'S OWN precision, not the amount field's.
                //
                // `formatToDecimal` truncates (`roundingMode = .down`) and chains
                // settle in whole base units, so truncating at `coin.decimals`
                // reproduces the payout rather than approximating it. Four
                // decimals — the precision of the amount FIELD — understated a
                // 2002.74 TCY withdrawal by 0.000044 and rendered a dust
                // position's full exit as a flat "0"; the field's precision is a
                // property of the field, and what this screen has to state is
                // what the chain will pay.
                //
                // Not `formatForDisplay`: it abbreviates past a million ("1.2M
                // TCY" is not a figure anyone can check against what they asked
                // for) and, below a million, ignores its own `maxDecimals`.
                amount: amount.formatToDecimal(digits: transaction.coin.decimals),
                ticker: transaction.coin.ticker,
                logo: transaction.coin.logo
            )
        )
    }
}
