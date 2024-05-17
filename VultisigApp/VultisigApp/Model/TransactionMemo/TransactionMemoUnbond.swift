//
//  TransactionMemoUnbond.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoUnbond: TransactionMemoAddressable, ObservableObject {
    @Published var nodeAddress: String = ""
    @Published var amount: Double = 0.0
    @Published var provider: String = ""
    
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
    
    required init() {}
    
    init(nodeAddress: String, amount: Double = 0.0, provider: String = "") {
        self.nodeAddress = nodeAddress
        self.amount = amount
        self.provider = provider
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "UNBOND:\(self.nodeAddress):\(self.amount)"
        if !self.provider.isEmpty {
            memo += ":\(self.provider)"
        }
        return memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("amount", "\(self.amount)")
        dict.set("provider", self.provider)
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            TransactionMemoAddressTextField(memo: self, addressKey: "nodeAddress")
            StyledFloatingPointField(placeholder: "Amount", value: Binding(
                get: { self.amount },
                set: { self.amount = $0 }
            ), format: .number)
            TransactionMemoAddressTextField(memo: self, addressKey: "provider")
        })
    }
}
