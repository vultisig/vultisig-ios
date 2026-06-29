//
//  SolanaMoveStakeTransactionViewModel.swift
//  VultisigApp
//
//  Form view-model for the Solana move-stake (redelegate A → B) flow. Solana
//  has no native redelegate, so the move is guided and multi-step: this screen
//  confirms the source account + destination validator and kicks off the FIRST
//  sub-step — deactivating the moved account so its ~1-epoch cooldown begins.
//  Once the account has cooled down the user returns via the "Finish moving to
//  B" resume CTA, which signs the re-delegate sub-step.
//
//  v1 moves the WHOLE source account (no on-chain split), so there is no amount
//  field — the account's full delegated stake moves to B. The fee is reserved
//  from the liquid balance so a move never burns a ceremony for lack of fee.
//

import Foundation
import Combine

@MainActor
final class SolanaMoveStakeTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    /// The account being moved (delegated to the origin validator A).
    let sourceStakeAccount: SolanaStakeAccount

    @Published var validForm: Bool = false
    @Published var selectedValidator: SolanaValidator?

    private(set) lazy var form: [FormField] = []

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(coin: Coin, vault: Vault, sourceStakeAccount: SolanaStakeAccount) {
        self.coin = coin
        self.vault = vault
        self.sourceStakeAccount = sourceStakeAccount
    }

    func onLoad() {
        setupForm()
        validForm = selectedValidator != nil
    }

    /// The amount being moved — the source account's full delegated stake,
    /// human-decimal. A whole-account move carries no editable amount.
    var movedAmount: Decimal {
        let staked = sourceStakeAccount.delegation?.stake ?? 0
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(staked) / divisor
    }

    /// Network fee for the deactivate sub-step in human-decimal SOL — the flat
    /// base + priority fee the transfer path uses. Each move sub-step pays a fee
    /// from the liquid balance.
    var feeDecimal: Decimal {
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(string: SolanaHelper.defaultFeeInLamports.description).map { $0 / divisor } ?? 0
    }

    /// Fail-closed when the liquid balance can't cover the deactivate fee.
    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal >= feeDecimal
    }

    /// Multi-step / cross-epoch explanation surfaced on the input screen so the
    /// user accepts that the move spans epochs before confirming.
    var multiStepMessage: String {
        let epochs = 1
        let days = SolanaStakingCooldownEstimate.approximateDays(epochs: epochs)
        return String(format: "solanaMoveStakeMultiStepNotice".localized, epochs, days)
    }

    /// Builds the FIRST sub-step: deactivate the moved account so its cooldown
    /// starts. `amount` is unused by `.deactivate` (whole account cools down).
    var transactionBuilder: TransactionBuilder? {
        guard hasSufficientBalanceForFee, let validator = selectedValidator else { return nil }
        return SolanaMoveStakeTransactionBuilder(
            coin: coin,
            stakeAccount: sourceStakeAccount.pubkey,
            votePubkey: validator.votePubkey,
            step: .deactivate,
            amount: "0"
        )
    }
}
