
//
//  TransactionMemoUnbond.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoUnstake: TransactionMemoAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = false
    
    @Published var nodeAddress: String = ""
    @Published var amount: Double = 0.0
    @Published var provider: String = ""
    
    // Internal
    @Published var nodeAddressValid: Bool = false
    @Published var amountValid: Bool = false
    @Published var providerValid: Bool = true
    
    private var cancellables = Set<AnyCancellable>()
    
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
    
    required init() {
        setupValidation()
    }
    
    init(nodeAddress: String, amount: Double = 0.0, provider: String = "") {
        self.nodeAddress = nodeAddress
        self.amount = amount
        self.provider = provider
        setupValidation()
    }
    
    private func setupValidation() {
        Publishers.CombineLatest3($nodeAddressValid, $amountValid, $providerValid)
            .map { $0 && $1 && $2 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    var amountInUnits: String {
        let amountInSats = Int64(self.amount * pow(10, 8))
        return amountInSats.description
    }
    
    func toString() -> String {
        var memo = "UNBOND:\(self.nodeAddress):\(amountInUnits)"
        if !self.provider.isEmpty {
            memo += ":\(self.provider)"
        }
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("Unbond amount", "\(self.amount)")
        dict.set("provider", self.provider)
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

            StyledFloatingPointField(
                placeholder: "Amount",
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

            TransactionMemoAddressTextField(
                memo: self,
                addressKey: "provider",
                isOptional: true,
                isAddressValid: Binding(
                    get: { self.providerValid },
                    set: { self.providerValid = $0 }
                )
            )
        })
    }
}
