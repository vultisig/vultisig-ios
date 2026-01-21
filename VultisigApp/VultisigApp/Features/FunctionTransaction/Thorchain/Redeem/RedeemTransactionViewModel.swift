//
//  RedeemTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class RedeemTransactionViewModel: ObservableObject, Form {
    let yCoin: Coin
    let coin: CoinMeta
    let vault: Vault

    @Published var percentageSelected: Double? = 100
    @Published var slippage: Double? = 1
    @Published var validForm: Bool = false
    @Published var amountField = FormField(label: "amount".localized)

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(yCoin: Coin, coin: CoinMeta, vault: Vault) {
        self.coin = coin
        self.yCoin = yCoin
        self.vault = vault
    }

    func onLoad() {
        setupForm()
        setupAmountField()
    }

    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm else { return nil }
        return RedeemTransactionBuilder(
            coin: yCoin,
            amount: amountField.value,
            sendMaxAmount: isMaxAmount,
            slippage: Decimal(slippage ?? 1.0) / 100
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }

    func setupAmountField() {
        self.amountField.validators = [
            AmountBalanceValidator(balance: yCoin.balanceDecimal)
        ]
        self.percentageSelected = 100
        self.isMaxAmount = true
    }
}
