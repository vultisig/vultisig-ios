//
//  CancelLimitOrderTransactionViewModel.swift
//  VultisigApp
//

import Foundation

@MainActor
final class CancelLimitOrderTransactionViewModel: ObservableObject {
    let coin: Coin
    let vault: Vault
    let request: LimitOrderCancelRequest

    init(coin: Coin, vault: Vault, request: LimitOrderCancelRequest) {
        self.coin = coin
        self.vault = vault
        self.request = request
    }

    /// The deposit gas the cancel will actually be signed with, in human units.
    /// Read from the shared constant so this pre-flight and the signed fee
    /// cannot disagree.
    var feeDecimal: Decimal {
        Decimal(THORChainConstants.depositGasBaseUnits) / pow(Decimal(10), coin.decimals)
    }

    /// The cancel sends no coins, so the only balance question is whether the
    /// fee is covered — but it has to be the REAL fee, not merely a non-zero
    /// balance. A dust account would otherwise get an enabled Continue button
    /// and a rejection two screens later, with nothing explaining why.
    ///
    /// Deliberately checks the RUNE balance rather than the order's source
    /// asset: a secured-asset order is cancelled by a `MsgDeposit` whose fee is
    /// charged in RUNE against the account, not taken out of anything the order
    /// holds.
    var hasSufficientBalance: Bool {
        coin.balanceDecimal >= feeDecimal
    }

    /// True when another resting order shares this one's THORChain bucket, so
    /// the cancel may close a different order than the one the user opened.
    var hasDuplicateWarning: Bool {
        request.duplicateRestingOrderCount > 0
    }

    var transactionBuilder: TransactionBuilder? {
        guard hasSufficientBalance else { return nil }
        return CancelLimitOrderTransactionBuilder(coin: coin, request: request)
    }
}
