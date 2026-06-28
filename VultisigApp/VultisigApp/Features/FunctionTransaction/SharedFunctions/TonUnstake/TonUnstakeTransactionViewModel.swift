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
    /// Pool implementation (`whales`, `tf`, …) that resolves the withdraw comment.
    let poolImplementation: String?
    /// Currently staked amount, shown for confirmation. Nominator pools support
    /// full withdrawal only, so the user does not pick an amount.
    let stakedAmount: Decimal

    /// Fixed amount that accompanies the withdrawal message (the 0.2 TON
    /// deposit/withdraw fee per the Whales pool spec). On-chain, a "Withdraw"
    /// carrying this fee is accepted and the pool returns the full staked
    /// balance, whereas a larger signal (e.g. 1 TON) is rejected.
    private static let withdrawalSignalAmount: Decimal = Decimal(string: "0.2") ?? 0.2

    init(coin: Coin, vault: Vault, poolAddress: String, poolImplementation: String?, stakedAmount: Decimal) {
        self.coin = coin
        self.vault = vault
        self.poolAddress = poolAddress
        self.poolImplementation = poolImplementation
        self.stakedAmount = stakedAmount
    }

    /// Whether the liquid balance can cover the 0.2-TON withdrawal signal plus the
    /// network fee. Without it the withdraw message would fail to broadcast.
    var hasSufficientBalance: Bool {
        let fee = TonHelper.defaultFee.description.toDecimal() / pow(Decimal(10), coin.decimals)
        return coin.balanceDecimal >= Self.withdrawalSignalAmount + fee
    }

    /// Withdraw text comment for the pool, resolved from its implementation
    /// (`whales` → "Withdraw", `tf` → "w"). `nil` for an unsupported/unknown
    /// implementation — the build is blocked rather than sending a guessed
    /// comment the pool contract would reject.
    var withdrawComment: String? {
        TonStakingComment.withdraw(for: poolImplementation)
    }

    var transactionBuilder: TransactionBuilder? {
        guard hasSufficientBalance, let memo = withdrawComment else { return nil }
        return TonUnstakeTransactionBuilder(
            coin: coin,
            amount: Self.withdrawalSignalAmount.formatToDecimal(digits: coin.decimals),
            poolAddress: poolAddress,
            memo: memo
        )
    }
}
