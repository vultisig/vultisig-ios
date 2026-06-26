//
//  SolanaUnstakeTransactionViewModel.swift
//  VultisigApp
//
//  Form view-model for the Solana deactivate (unstake) flow. The stake account
//  is pre-selected by the caller (from a position card); there's no amount field
//  — a deactivate cools down the WHOLE account, so the screen only confirms the
//  account and surfaces the ~1-epoch cooldown copy before the user proceeds.
//  Mirrors `CosmosUndelegateTransactionViewModel` minus the amount.
//

import Foundation
import Combine

@MainActor
final class SolanaUnstakeTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    /// Stake account being deactivated. Surfaced read-only for the user to
    /// confirm; the whole account's delegated stake cools down.
    let stakeAccount: SolanaStakeAccount

    @Published var validForm: Bool = true

    private(set) lazy var form: [FormField] = []

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(coin: Coin, vault: Vault, stakeAccount: SolanaStakeAccount) {
        self.coin = coin
        self.vault = vault
        self.stakeAccount = stakeAccount
    }

    func onLoad() {
        setupForm()
    }

    /// Network fee for a deactivate tx in human-decimal SOL — the flat base +
    /// priority fee the transfer path uses.
    var feeDecimal: Decimal {
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(string: SolanaHelper.defaultFeeInLamports.description).map { $0 / divisor } ?? 0
    }

    /// The fee is paid from the liquid (spendable) balance, not the staked
    /// pool — fail closed when it can't be covered so we never burn a ceremony.
    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal >= feeDecimal
    }

    /// Cooldown copy — a deactivate begins a ~1-epoch cooldown; the funds become
    /// withdrawable only once the network epoch advances past the account's
    /// deactivation epoch. Surfaced on the input screen so the user accepts the
    /// wait before confirming.
    var cooldownMessage: String {
        let epochs = 1
        let days = SolanaStakingCooldownEstimate.approximateDays(epochs: epochs)
        return String(format: "solanaStakingDeactivatingNotice".localized, epochs, days)
    }

    var transactionBuilder: TransactionBuilder? {
        guard hasSufficientBalanceForFee else { return nil }
        return SolanaUnstakeTransactionBuilder(coin: coin, stakeAccount: stakeAccount.pubkey)
    }
}
