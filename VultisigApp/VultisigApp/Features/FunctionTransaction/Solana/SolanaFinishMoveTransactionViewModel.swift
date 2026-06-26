//
//  SolanaFinishMoveTransactionViewModel.swift
//  VultisigApp
//
//  Resume step of a guided Solana move-stake — "Finish moving to B". Reached
//  when a cooled-down (inactive) move-origin account is detected; signs the
//  re-delegate sub-step that delegates the moved account to validator B. The
//  destination validator is carried in from the inferred move progress, so the
//  screen only confirms before proceeding.
//

import Foundation
import Combine

@MainActor
final class SolanaFinishMoveTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    /// The cooled-down account to re-delegate to B.
    let movedStakeAccount: SolanaStakeAccount
    /// Destination validator (B).
    let destinationValidator: SolanaValidator

    @Published var validForm: Bool = true

    private(set) lazy var form: [FormField] = []

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(
        coin: Coin,
        vault: Vault,
        movedStakeAccount: SolanaStakeAccount,
        destinationValidator: SolanaValidator
    ) {
        self.coin = coin
        self.vault = vault
        self.movedStakeAccount = movedStakeAccount
        self.destinationValidator = destinationValidator
    }

    func onLoad() {
        setupForm()
    }

    /// The lamports being re-delegated to B — the moved account's withdrawable
    /// balance net of the rent-exempt reserve.
    private var redelegatableLamports: UInt64 {
        movedStakeAccount.lamports > movedStakeAccount.rentExemptReserve
            ? movedStakeAccount.lamports - movedStakeAccount.rentExemptReserve
            : 0
    }

    var movedAmount: Decimal {
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(redelegatableLamports) / divisor
    }

    var feeDecimal: Decimal {
        let divisor = pow(Decimal(10), coin.decimals)
        return Decimal(string: SolanaHelper.defaultFeeInLamports.description).map { $0 / divisor } ?? 0
    }

    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal >= feeDecimal
    }

    var transactionBuilder: TransactionBuilder? {
        guard hasSufficientBalanceForFee, redelegatableLamports > 0 else { return nil }
        let divisor = pow(Decimal(10), coin.decimals)
        let amount = (Decimal(redelegatableLamports) / divisor).description
        return SolanaMoveStakeTransactionBuilder(
            coin: coin,
            stakeAccount: movedStakeAccount.pubkey,
            votePubkey: destinationValidator.votePubkey,
            step: .redelegate,
            amount: amount
        )
    }
}
