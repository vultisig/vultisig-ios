//
//  QuotedWithdrawalPresentation.swift
//  VultisigApp
//
//  Presents a builder-quoted withdrawal payout instead of the transaction
//  carrier's zero amount.
//

import Foundation

enum QuotedWithdrawalPresentation {

    /// Uses the builder's quote so presentation cannot re-derive from a different
    /// position than the form used.
    static func hero(for transaction: SendTransaction) -> HeroContent? {
        guard let amount = transaction.withdrawDisplayAmount else { return nil }
        // Prefer the signed operation's verb over the neutral fallback.
        let decoded = SignedTransactionDecoder.decode(InitiatingTransactionContent(transaction))
        let title = DecodedTransactionPresentation.title(for: decoded.operation) ?? "quotedWithdrawalVerifyTitle".localized
        let coin = HeroCoinAmount(
            // Match base-unit settlement by truncating at the asset's precision;
            // abbreviated display formatting would hide the exact payout.
            amount: amount.formatToDecimal(digits: transaction.coin.decimals),
            ticker: transaction.coin.ticker,
            logo: transaction.coin.logo
        )
        if let projected = ProjectionCoordinator.hero(for: decoded, title: title, estimate: coin) {
            return projected
        }
        return .send(title: title, coin: coin)
    }
}
