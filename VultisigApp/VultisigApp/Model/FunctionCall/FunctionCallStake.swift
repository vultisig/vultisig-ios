//
//  FunctionCallStake.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/10/24.

import SwiftUI
import Foundation
import Combine

class FunctionCallStake: FunctionCallAddressable, ObservableObject {
    @Published var amount: Decimal = 0
    @Published var nodeAddress: String = ""

    // Internal
    @Published var amountValid: Bool = false
    @Published var nodeAddressValid: Bool = false
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil

    var addressFields: [String: String] {
        get {
            let fields = ["nodeAddress": nodeAddress]
            return fields
        }
        set {
            if let value = newValue["nodeAddress"] {
                nodeAddress = value
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var tx: SendTransaction?

    required init() {
    }

    convenience init(tx: SendTransaction) {
        self.init()
        self.tx = tx
        self.amount = tx.coin.balanceDecimal
    }

    func initialize() {
        setupValidation()
    }

    var balance: String {
        guard let tx = tx else { return "( Balance: 0 TON )" }
        let balance = tx.coin.balanceDecimal.formatForDisplay()
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }

    private func setupValidation() {
        $amount
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.validateAmount()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest($amountValid, $nodeAddressValid)
            .map { $0 && $1 && !self.amount.isZero }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }

    private func validateAmount() {
        guard let tx = tx else {
            amountValid = false
            customErrorMessage = "Transaction not available"
            return
        }

        let balance = tx.coin.balanceDecimal
        let isValidAmount = amount > 0 && amount <= balance
        amountValid = isValidAmount

        if amount <= 0 {
            amountValid = false
            self.customErrorMessage = NSLocalizedString("insufficientBalanceForFunctions", comment: "Error message when amount is invalid")
        } else if balance < amount {
            amountValid = false
            self.customErrorMessage = NSLocalizedString("insufficientBalanceForFunctions", comment: "Error message when user tries to enter amount greater than available balance")
        } else {
            self.customErrorMessage = nil
        }
    }

    var description: String {
        return toString()
    }

    func toString() -> String {
        return "d"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("memo", self.toString())
        return dict
    }

    func getView() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 12) {
            FunctionCallAddressTextField(
                memo: self,
                addressKey: "nodeAddress",
                isAddressValid: Binding(
                    get: { self.nodeAddressValid },
                    set: { self.nodeAddressValid = $0 }
                )
            )

            VStack(alignment: .leading, spacing: 8) {
                StyledFloatingPointField(
                    label: NSLocalizedString("amount", comment: ""),
                    placeholder: NSLocalizedString("enterAmount", comment: ""),
                    value: Binding(
                        get: { self.amount },
                        set: { self.amount = $0 }
                    ),
                    isValid: Binding(
                        get: { self.amountValid },
                        set: { self.amountValid = $0 }
                    ))

                Text(balance)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let errorMessage = customErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }.onAppear {
            self.initialize()
        })
    }
}
