//
//  TonUnstakeTransactionViewModel.swift
//  VultisigApp
//

import Foundation
import BigInt

@MainActor
final class TonUnstakeTransactionViewModel: ObservableObject {
    let coin: Coin
    let vault: Vault
    let poolAddress: String
    /// Currently staked amount, shown for confirmation. Nominator pools support
    /// full withdrawal only, so the user does not pick an amount.
    let stakedAmount: Decimal

    /// Fixed amount that accompanies the "w" withdrawal message (1 TON, mirroring
    /// the legacy FunctionCall unstake). The pool returns the staked balance.
    private static let withdrawalSignalAmount: Decimal = 1

    init(coin: Coin, vault: Vault, poolAddress: String, stakedAmount: Decimal) {
        self.coin = coin
        self.vault = vault
        self.poolAddress = poolAddress
        self.stakedAmount = stakedAmount
    }

    /// Whether the liquid balance can cover the 1-TON withdrawal signal plus the
    /// network fee. Without it the "w" message would fail to broadcast.
    var hasSufficientBalance: Bool {
        let fee = TonHelper.defaultFee.description.toDecimal() / pow(Decimal(10), coin.decimals)
        return coin.balanceDecimal >= Self.withdrawalSignalAmount + fee
    }

    var transactionBuilder: TransactionBuilder? {
        guard hasSufficientBalance else { return nil }
        return TonUnstakeTransactionBuilder(
            coin: coin,
            amount: Self.withdrawalSignalAmount.formatToDecimal(digits: coin.decimals),
            poolAddress: poolAddress
        )
    }
}
