//
//  TonLiquidStakeTransactionViewModel.swift
//  VultisigApp
//

import Foundation
import Combine
import BigInt

@MainActor
final class TonLiquidStakeTransactionViewModel: ObservableObject, Form {
    /// Native TON coin — funds the Tonstakers deposit.
    let coin: Coin
    let vault: Vault

    @Published var validForm: Bool = false

    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0",
        validators: [RequiredValidator(errorMessage: "emptyAmountField".localized)]
    )

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    /// Tonstakers enforces a 1-TON minimum deposit.
    var minStake: Decimal {
        TonstakersConstants.minStakeNano.description.toDecimal() / pow(Decimal(10), coin.decimals)
    }

    /// Network fee (TON `defaultFee`) reserved from the spendable balance.
    var feeDecimal: Decimal {
        TonHelper.defaultFee.description.toDecimal() / pow(Decimal(10), coin.decimals)
    }

    var maxStakeableAmount: Decimal {
        let remaining = coin.balanceDecimal - feeDecimal
        return remaining > 0 ? remaining : 0
    }

    var hasSufficientBalanceForFee: Bool {
        coin.balanceDecimal > feeDecimal
    }

    init(coin: Coin, vault: Vault) {
        self.coin = coin
        self.vault = vault
    }

    func onLoad() {
        setupForm()
        amountField.validators.append(AmountBalanceValidator(balance: maxStakeableAmount))
        amountField.validators.append(
            ClosureValidator { [weak self] value in
                guard let self else { return }
                let amount = value.toDecimal()
                if amount < self.minStake {
                    throw MinStakeError.belowMinimum(self.minStake, self.coin.chain.ticker)
                }
            }
        )
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm, hasSufficientBalanceForFee else { return nil }
        return TonLiquidStakeTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals)
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
}
