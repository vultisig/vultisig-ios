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
    @Published private var sendTx = SendTransaction()
    
    @Published var validForm: Bool = false
    
    @Published var addressField = FormField(
        label: "address".localized,
        placeholder: "enterAddress".localized,
        validators: [AddressValidator(chain: .thorChain)]
    )
    @Published var providerField = FormField(
        label: "Provider (optional)".localized,
        placeholder: "provider".localized,
        validators: [AddressValidator(chain: .thorChain)]
    )
    @Published var amountField = FormField(
        label: "amount".localized,
        placeholder: "0 RUNE"
    )
    @Published var operatorFee = FormField(
        label: "Operator-fees (Basis Points)".localized,
        placeholder: "0"
    )
    
    private(set) lazy var form: [FormField] = [
        addressField,
        providerField,
        amountField,
        operatorFee
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
    }
    
    func handle(addressResult: AddressResult?, isProvider: Bool) {
        guard let addressResult else { return }
        if isProvider {
            providerField.value = addressResult.address
        } else {
            addressField.value = addressResult.address
        }
    }
    
    func buildTransaction() -> SendTransaction? {
        guard validForm else { return nil }
        
        if operatorFee.value != .empty && (providerField.value == .empty || !providerField.valid) {
            return nil
        }
        
        // TODO: - Set max amount
        sendTx.sendMaxAmount = sendTx.amountDecimal == coin.balanceDecimal
        return sendTx
    }
    
    func onPercentage(_ percentage: Int) {
        let max = coin.balanceDecimal
        let multiplier = (Decimal(percentage) / 100)
        let amountDecimal = max * multiplier
        sendTx.amount = amountDecimal.formatToDecimal(digits: coin.decimals)
        amountField.value = sendTx.amount
    }
}
