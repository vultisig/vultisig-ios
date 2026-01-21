//
//  MintTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class MintTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let yCoin: CoinMeta
    let vault: Vault

    @Published var percentageSelected: Double? = 100
    @Published var validForm: Bool = false
    @Published var amountField = FormField(label: "amount".localized)

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(coin: Coin, yCoin: CoinMeta, vault: Vault) {
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
        return MintTransactionBuilder(
            coin: coin,
            amount: amountField.value,
            sendMaxAmount: isMaxAmount
        )
    }

    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }

    func setupAmountField() {
        self.amountField.validators = [
            AmountBalanceValidator(balance: coin.balanceDecimal)
        ]
        self.percentageSelected = 100
    }
}
