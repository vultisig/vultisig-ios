//
//  AddLPTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class AddLPTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let coin2: Coin
    let vault: Vault
    let position: LPPosition

    @Published var percentageSelected: Double? = 100
    @Published var slippage: Double? = 1
    @Published var validForm: Bool = false
    @Published var amountField = FormField(label: "amount".localized)

    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [amountField]

    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()

    init(coin: Coin, coin2: Coin, vault: Vault, position: LPPosition) {
        self.coin = coin
        self.coin2 = coin2
        self.vault = vault
        self.position = position
    }

    func onLoad() {
        setupForm()
        setupAmountField()
    }

    var transactionBuilder: TransactionBuilder? {
        guard validForm, let poolName = position.poolName else { return nil }
        return AddLPTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
            poolName: poolName,
            pairedAddress: pairedAddress,
            sendMaxAmount: isMaxAmount
        )
    }

    var pairedAddress: String? {
        switch coin.chain {
        case .thorChain:
            coin2.address
        case .mayaChain:
            // MayaChain doesn't need pair address
            nil
        default:
            coin2.address
        }
    }

    var showAsymmetricDepositInfo: Bool {
        coin.chain == .mayaChain
    }

    var asymmetricDepositMessage: String {
        "asymmetricDepositInfo".localized
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
