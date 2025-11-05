//
//  UnstakeTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class UnstakeTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    
    @Published var validForm: Bool = false
    @Published private(set) var stakedAmount: Decimal = 0
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0 RUNE"
    )
    
    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        amountField
    ]
    
    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()
    
    init(coin: Coin, vault: Vault) {
        self.coin = coin
        self.vault = vault
    }
    
    func onLoad() {
        setupForm()
//        amountField.value = bondNodeFormattedAmount.formatForDisplay(maxDecimals: coin.decimals)
    }
    
    var transactionBuilder: TransactionBuilder? {
        guard validForm else { return nil }
        return nil
//        return UnbondTransactionBuilder(
//            coin: coin,
//            unbondAmount: amountField.value.formatToDecimal(digits: coin.decimals),
//            sendMaxAmount: isMaxAmount,
//            nodeAddress: addressViewModel.field.value,
//            providerAddress: providerViewModel.field.value
//        )
    }
    
    func onPercentage(_ percentage: Int) {
        isMaxAmount = percentage == 100
    }
    
//    func updateAmountValidation() {
//        var validators: [FormFieldValidator] = [RequiredValidator(errorMessage: "emptyAmountField".localized)]
//        if let bondNode {
//            bondNodeFormattedAmount = coin.valueWithDecimals(value: bondNode.bond)
//            validators.append(AmountBalanceValidator(balance: bondNodeFormattedAmount))
//        } else {
//            bondNodeFormattedAmount = 0
//        }
//        amountField.validators = validators
//    }
}
