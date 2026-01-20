//
//  UnbondTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class UnbondTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let bondAddress: String
    
    @Published private(set) var bondNode: RuneBondNode?
    @Published private(set) var bondNodeFormattedAmount: Decimal = 0
    @Published var validForm: Bool = false
    
    @Published var addressViewModel: AddressViewModel
    @Published var providerViewModel: AddressViewModel
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0 RUNE"
    )
    
    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        addressViewModel.field,
        amountField
    ]
    
    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()
    
    init(coin: Coin, vault: Vault, bondAddress: String) {
        self.coin = coin
        self.vault = vault
        self.bondAddress = bondAddress
        self.addressViewModel = AddressViewModel(
            coin: coin,
            additionalValidators: [RequiredValidator(errorMessage: "emptyAddressField".localized)]
        )
        self.providerViewModel = AddressViewModel(label: "providerLabel".localized, coin: coin)
    }
    
    func onLoad() {
        setupForm()
        addressViewModel.field.value = bondAddress
        selectBondNode()
        amountField.value = bondNodeFormattedAmount.formatForDisplay(maxDecimals: coin.decimals)
    }
    
    var transactionBuilder: TransactionBuilder? {
        validateErrors()
        guard validForm else { return nil }
        return UnbondTransactionBuilder(
            coin: coin,
            unbondAmount: amountField.value.formatToDecimal(digits: coin.decimals),
            sendMaxAmount: isMaxAmount,
            nodeAddress: addressViewModel.field.value,
            providerAddress: providerViewModel.field.value
        )
    }
    
    func onPercentage(_ percentage: Double) {
        isMaxAmount = percentage == 100
    }
    
    func selectBondNode() {
        let address = addressViewModel.field.value
        let bondNode = coin.bondedNodes.first(where: { $0.address == address })
        self.bondNode = bondNode
        updateAmountValidation()
    }
     
    func updateAmountValidation() {
        var validators: [FormFieldValidator] = [RequiredValidator(errorMessage: "emptyAmountField".localized)]
        if let bondNode {
            bondNodeFormattedAmount = coin.valueWithDecimals(value: bondNode.bond)
            validators.append(AmountBalanceValidator(balance: bondNodeFormattedAmount))
        } else {
            bondNodeFormattedAmount = 0
        }
        amountField.validators = validators
    }
}
