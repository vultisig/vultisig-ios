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
    @Published var sendTx = SendTransaction()
    
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
    @Published var operatorFee = FormField(
        label: "operatorFeesLabel".localized,
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
        operatorFee.validators = [
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
    
    func buildTransaction() -> SendTransaction? {
        guard validForm else { return nil }
        
        sendTx.coin = coin
        sendTx.sendMaxAmount = sendTx.amountDecimal == coin.balanceDecimal
        sendTx.amount = amountField.value.formatToDecimal(digits: coin.decimals)
        sendTx.memo = buildMemo()
        sendTx.memoFunctionDictionary = buildDictionary()
        sendTx.transactionType = .unspecified
        sendTx.wasmContractPayload = nil
        sendTx.toAddress = ""
                
        return sendTx
    }
    
    func onPercentage(_ percentage: Int) {
        let max = coin.balanceDecimal
        let multiplier = (Decimal(percentage) / 100)
        let amountDecimal = max * multiplier
        sendTx.amount = amountDecimal.formatToDecimal(digits: coin.decimals)
        amountField.value = sendTx.amount
    }
    
    func buildMemo() -> String {
        var memo = "BOND:\(addressField.value)"
        if !providerField.value.isEmpty {
            memo += ":\(providerField.value)"
        }
        let operatorFeeInt = Int64(operatorFee.value)
        if let operatorFeeInt, operatorFeeInt != .zero {
            if providerField.value.isEmpty {
                memo += "::\(operatorFeeInt)"
            } else {
                memo += ":\(operatorFeeInt)"
            }
        }
        return memo
    }
    
    func buildDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", addressField.value)
        dict.set("provider", providerField.value)
        dict.set("fee", "\(Int64(operatorFee.value) ?? 0)")
        dict.set("memo", buildMemo())
        return dict
    }
}
