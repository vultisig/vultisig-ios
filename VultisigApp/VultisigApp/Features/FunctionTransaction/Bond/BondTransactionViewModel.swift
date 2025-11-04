//
//  BondTransactionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/10/2025.
//

import Foundation
import Combine

final class BondTransactionViewModel: ObservableObject, Form {
    let coin: Coin
    let vault: Vault
    let initialBondAddress: String?
    
    @Published var validForm: Bool = false
    
    @Published var addressField = FormField(
        label: "address".localized,
        placeholder: "enterAddress".localized,
        validators: [
            RequiredValidator(errorMessage: "emptyAddressField".localized),
            AddressValidator(chain: .thorChain)
        ]
    )
    @Published var providerField = FormField(
        label: "providerLabel".localized,
        placeholder: "provider".localized,
        validators: [AddressValidator(chain: .thorChain)]
    )
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0 RUNE",
        validators: [
            RequiredValidator(errorMessage: "emptyAmountField".localized)
        ]
    )
    @Published var operatorFeeField = FormField(
        label: "operatorFeesLabel".localized,
        placeholder: "0"
    )
    
    private(set) var isMaxAmount: Bool = false
    private(set) lazy var form: [FormField] = [
        addressField,
        providerField,
        amountField,
        operatorFeeField
    ]
    
    var formCancellable: AnyCancellable?
    var cancellables = Set<AnyCancellable>()
    
    init(coin: Coin, vault: Vault, initialBondAddress: String?) {
        self.coin = coin
        self.vault = vault
        self.initialBondAddress = initialBondAddress
    }
    
    func onLoad() {
        setupForm()
        operatorFeeField.validators = [
            ClosureValidator { value in
                if value.isEmpty && self.providerField.valid {
                    throw HelperError.runtimeError("operatorFeesError".localized)
                }
            }
        ]
        
        amountField.validators.append(AmountBalanceValidator(balance: coin.balanceDecimal))
        
        if let initialBondAddress {
            addressField.value = initialBondAddress
        }
    }
    
    func handle(addressResult: AddressResult?, isProvider: Bool) {
        guard let addressResult else { return }
        if isProvider {
            providerField.value = addressResult.address
        } else {
            addressField.value = addressResult.address
        }
    }
    
    var transactionBuilder: TransactionBuilder? {
        guard validForm else { return nil }
        
        return BondTransactionBuilder(
            coin: coin,
            amount: amountField.value.formatToDecimal(digits: coin.decimals),
            sendMaxAmount: isMaxAmount,
            nodeAddress: addressField.value,
            providerAddress: providerField.value,
            operatorFee: Int64(operatorFeeField.value)
        )
    }
    
    func onPercentage(_ percentage: Int) {
        isMaxAmount = percentage == 100
    }
}
