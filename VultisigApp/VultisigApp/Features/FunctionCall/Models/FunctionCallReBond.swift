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
    @Published var rebondAmount: Decimal = 0.0  // Amount to rebond (goes in memo only)
    @Published var nodeAddress: String = ""
    @Published var newAddress: String = ""

    // Internal
    @Published var rebondAmountValid: Bool = true  // Optional field, defaults to all
    @Published var nodeAddressValid: Bool = false
    @Published var newAddressValid: Bool = false

    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil

    private var tx: SendTransaction
    private var vault: Vault

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

    required init(tx: SendTransaction, vault: Vault) {
        self.tx = tx
        self.vault = vault
    }

    func initialize() {
        // Ensure RUNE token is selected for REBOND operations on THORChain
        DispatchQueue.main.async {
            if let runeCoin = self.vault.runeCoin {
                self.tx.coin = runeCoin
            }
        }
        setupValidation()
        validateRuneToken()
    }

    // IMPORTANT: For REBOND, the actual transaction amount must be 0
    // The rebondAmount is only used in the memo
    var amount: Decimal {
        return 0  // REBOND transactions must send 0 RUNE
    }

    var balance: String {
        let balance = tx.coin.balanceDecimal.formatForDisplay()

        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }

    private func setupValidation() {
        // Combine validators
        Publishers.CombineLatest3($rebondAmountValid, $nodeAddressValid, $newAddressValid)
            .map { amountValid, nodeValid, newValid in
                // Check all validations
                let basicValid = amountValid && nodeValid && newValid

                // Clear error if validation passes
                if basicValid {
                    self.customErrorMessage = nil
                }

                return basicValid
            }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)

        // Watch for rebond amount changes - just validate it's a positive number or 0
        $rebondAmount
            .sink { [weak self] newAmount in
                guard let self = self else { return }
                // Rebond amount of 0 is valid (means transfer all)
                // Any positive amount is also valid
                self.rebondAmountValid = newAmount >= 0
                if self.rebondAmountValid && self.nodeAddressValid && self.newAddressValid {
                    self.customErrorMessage = nil
                }
            }
            .store(in: &cancellables)
    }

    private func validateRuneToken() {
        // Ensure we're using RUNE for rebond operations
        if tx.coin.chain != .thorChain || !tx.coin.isNativeToken {
            customErrorMessage = NSLocalizedString("rebondRequiresRune", comment: "Error when not using RUNE for Rebond")
            isTheFormValid = false
        }
    }

    var description: String {
        return toString()
    }

    func toString() -> String {
        var memo = "REBOND:\(self.nodeAddress):\(self.newAddress)"
        // Amount is optional - if zero or equal to full bond, it will transfer all
        if self.rebondAmount > 0 {
            // Convert decimal amount to smallest unit (assuming 8 decimals for RUNE)
            // Use NSDecimalNumber for precise decimal scaling, then convert to Int64
            let amountInSmallestUnit = NSDecimalNumber(decimal: self.rebondAmount)
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
        if self.rebondAmount > 0 {
            dict.set("rebondAmount", "\(self.rebondAmount)")
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

            // Rebond Amount field (optional - if empty, transfers all bonded RUNE)
            // Note: This amount goes in the memo only, not in the transaction
            StyledFloatingPointField(
                label: "rebondAmount".localized,
                placeholder: "rebondAmountPlaceholder".localized,
                value: Binding(
                    get: { self.rebondAmount },
                    set: { newValue in
                        self.rebondAmount = newValue
                        self.rebondAmountValid = newValue >= 0
                    }
                ),
                isValid: Binding(
                    get: { self.rebondAmountValid },
                    set: { self.rebondAmountValid = $0 }
                ),
                isOptional: true
            )

            // Info message about transaction amount
            Text("rebondNote".localized)
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.horizontal)

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
