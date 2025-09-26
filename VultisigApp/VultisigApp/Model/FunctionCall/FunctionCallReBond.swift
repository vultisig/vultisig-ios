//
//  FunctionCallReBond.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 26/09/25.
//

import SwiftUI
import Foundation
import Combine

class FunctionCallReBond: FunctionCallAddressable, ObservableObject {
    @Published var amount: Decimal = 0.0
    @Published var nodeAddress: String = ""
    @Published var newAddress: String = ""
    
    // Internal
    @Published var amountValid: Bool = true  // Optional field, defaults to all
    @Published var nodeAddressValid: Bool = false
    @Published var newAddressValid: Bool = false
    
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil
    
    private var tx: SendTransaction
    private var vault: Vault
    private var functionCallViewModel: FunctionCallViewModel
    
    var addressFields: [String: String] {
        get {
            return [
                "nodeAddress": nodeAddress,
                "newAddress": newAddress
            ]
        }
        set {
            if let value = newValue["nodeAddress"] {
                nodeAddress = value
            }
            if let value = newValue["newAddress"] {
                newAddress = value
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(
        tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault
    ) {
        self.tx = tx
        self.vault = vault
        self.functionCallViewModel = functionCallViewModel
    }
    
    func initialize() {
        // Ensure RUNE token is selected for REBOND operations on THORChain
        if tx.coin.chain == .thorChain && !tx.coin.isNativeToken {
            DispatchQueue.main.async {
                self.functionCallViewModel.setRuneToken(to: self.tx, vault: self.vault)
            }
        }
        setupValidation()
        validateRuneToken()
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.formatForDisplay()
        
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }
    
    private func setupValidation() {
        // Combine validators and balance check
        Publishers.CombineLatest3($amountValid, $nodeAddressValid, $newAddressValid)
            .map { amountValid, nodeValid, newValid in
                // Check all validations
                let basicValid = amountValid && nodeValid && newValid
                
                // Additional validation: amount should not exceed balance
                if self.amount > 0 && self.amount > self.tx.coin.balanceDecimal {
                    self.customErrorMessage = "Insufficient balance. Available: \(self.tx.coin.balanceDecimal.formatForDisplay()) \(self.tx.coin.ticker)"
                    return false
                }
                
                // Clear error if validation passes
                if basicValid {
                    self.customErrorMessage = nil
                }
                
                return basicValid
            }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
        
        // Watch for amount changes to validate against balance
        $amount
            .sink { [weak self] newAmount in
                guard let self = self else { return }
                if newAmount > 0 {
                    if newAmount > self.tx.coin.balanceDecimal {
                        self.amountValid = false
                        self.customErrorMessage = "Amount exceeds available balance"
                    } else {
                        self.amountValid = true
                        if self.nodeAddressValid && self.newAddressValid {
                            self.customErrorMessage = nil
                        }
                    }
                } else {
                    // Amount of 0 is valid (means transfer all)
                    self.amountValid = true
                }
            }
            .store(in: &cancellables)
    }
    
    private func validateRuneToken() {
        // Ensure we're using RUNE for rebond operations
        if tx.coin.chain != .thorChain || !tx.coin.isNativeToken {
            customErrorMessage = "REBOND requires RUNE token on THORChain"
            isTheFormValid = false
        }
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "REBOND:\(self.nodeAddress):\(self.newAddress)"
        // Amount is optional - if zero or equal to full bond, it will transfer all
        if self.amount > 0 {
            // Convert decimal amount to smallest unit (assuming 8 decimals for RUNE)
            // Use NSDecimalNumber for precise decimal scaling, then convert to Int64
            let amountInSmallestUnit = NSDecimalNumber(decimal: self.amount)
                .multiplying(byPowerOf10: 8)
                .int64Value
            memo += ":\(amountInSmallestUnit)"
        }
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("newAddress", self.newAddress)
        if self.amount > 0 {
            dict.set("amount", "\(self.amount)")
        }
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            // Node Address field
            FunctionCallAddressTextField(
                memo: self,
                addressKey: "nodeAddress",
                isAddressValid: Binding(
                    get: { self.nodeAddressValid },
                    set: { self.nodeAddressValid = $0 }
                )
            )
            
            // New Address field (required)
            FunctionCallAddressTextField(
                memo: self,
                addressKey: "newAddress",
                isAddressValid: Binding(
                    get: { self.newAddressValid },
                    set: { self.newAddressValid = $0 }
                )
            )
            
            // Amount field (optional - if empty, transfers all bonded RUNE)
            StyledFloatingPointField(
                label: "\(NSLocalizedString("amount", comment: "")) \(self.balance) (Optional - leave empty to transfer all)",
                placeholder: NSLocalizedString("enterAmount", comment: ""),
                value: Binding(
                    get: { self.amount },
                    set: { newValue in
                        self.amount = newValue
                        // Validate amount doesn't exceed balance
                        if newValue > 0 && newValue > self.tx.coin.balanceDecimal {
                            self.amountValid = false
                            self.customErrorMessage = "Amount exceeds available balance"
                        } else {
                            self.amountValid = true
                            if self.nodeAddressValid && self.newAddressValid {
                                self.customErrorMessage = nil
                            }
                        }
                    }
                ),
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                ),
                isOptional: true
            )
            
            // Show error message if any
            if let errorMessage = self.customErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
        }.onAppear {
            self.initialize()
        })
    }
}
