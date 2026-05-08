//
//  SwapDraft+Adapter.swift
//  VultisigApp
//
//  Bridge between the legacy `SwapTransaction` class and the `SwapDraft` value
//  type during §1–§4. Lets new draft-based code paths interoperate with the
//  existing `@Published` plumbing without rewiring every caller at once.
//  Deleted alongside `SwapTransaction` in §5.
//

import Foundation

extension SwapDraft {
    init(from tx: SwapTransaction) {
        self.fromAmount = tx.fromAmount
        self.thorchainFee = tx.thorchainFee
        self.gas = tx.gas
        self.vultDiscountBps = tx.vultDiscountBps
        self.referralDiscountBps = tx.referralDiscountBps
        self.quote = tx.quote
        self.isFastVault = tx.isFastVault
        self.fastVaultPassword = tx.fastVaultPassword
        self.pendingRetryReason = tx.pendingRetryReason
        self.fromCoin = tx.fromCoin
        self.toCoin = tx.toCoin
        self.fromCoins = tx.fromCoins
        self.toCoins = tx.toCoins
    }

    func apply(to tx: SwapTransaction) {
        tx.fromAmount = fromAmount
        tx.thorchainFee = thorchainFee
        tx.gas = gas
        tx.vultDiscountBps = vultDiscountBps
        tx.referralDiscountBps = referralDiscountBps
        tx.quote = quote
        tx.isFastVault = isFastVault
        tx.fastVaultPassword = fastVaultPassword
        tx.pendingRetryReason = pendingRetryReason
        tx.fromCoin = fromCoin
        tx.toCoin = toCoin
        tx.fromCoins = fromCoins
        tx.toCoins = toCoins
    }
}
