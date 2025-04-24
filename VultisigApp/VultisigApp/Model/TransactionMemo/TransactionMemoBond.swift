//
//  TransactionMemoBond.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoBond: TransactionMemoAddressable, ObservableObject {
    @Published var amount: Double = 0.0
    @Published var nodeAddress: String = ""
    @Published var provider: String = ""
    @Published var fee: Int64 = .zero
    
    // Internal
    @Published var amountValid: Bool = false
    @Published var nodeAddressValid: Bool = false
    @Published var providerValid: Bool = true
    @Published var feeValid: Bool = true
    
    @Published var isTheFormValid: Bool = false
    
    private var tx: SendTransaction
    
    var addressFields: [String: String] {
        get {
            var fields = ["nodeAddress": nodeAddress]
            if !provider.isEmpty {
                fields["provider"] = provider
            }
            return fields
        }
        set {
            if let value = newValue["nodeAddress"] {
                nodeAddress = value
            }
            if let value = newValue["provider"] {
                provider = value
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(
        tx: SendTransaction, transactionMemoViewModel: TransactionMemoViewModel
    ) {
        self.tx = tx
        setupValidation()
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.description
        
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }
    
    private func setupValidation() {
        Publishers.CombineLatest4($amountValid, $nodeAddressValid, $providerValid, $feeValid)
            .map { $0 && $1 && $2 && $3 && (!self.provider.isEmpty ? self.fee != .zero : true) }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "BOND:\(self.nodeAddress)"
        if !self.provider.isEmpty {
            memo += ":\(self.provider)"
        }
        if self.fee != .zero {
            if self.provider.isEmpty {
                memo += "::\(self.fee)"
            } else {
                memo += ":\(self.fee)"
            }
        }
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("provider", self.provider)
        dict.set("fee", "\(self.fee)")
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            TransactionMemoAddressTextField(
                memo: self,
                addressKey: "nodeAddress",
                isAddressValid: Binding(
                    get: { self.nodeAddressValid },
                    set: { self.nodeAddressValid = $0 }
                )
            )
            TransactionMemoAddressTextField(
                memo: self,
                addressKey: "provider",
                isOptional: true,
                isAddressValid: Binding(
                    get: { self.providerValid },
                    set: { self.providerValid = $0 }
                )
            )
            
            StyledIntegerField(
                placeholder: "Operator's Fee",
                value: Binding(
                    get: { self.fee },
                    set: { self.fee = $0 }
                ),
                format: .number,
                isValid: Binding(
                    get: { self.feeValid },
                    set: { self.feeValid = $0 }
                ),
                isOptional: true
            )
            StyledFloatingPointField(
                placeholder: Binding(
                    get: { "Amount \(self.balance)" },
                    set: { _ in }
                ),
                value: Binding(
                    get: { self.amount },
                    set: { self.amount = $0 }
                ),
                format: .number,
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                )
            )
            
        })
    }
}
