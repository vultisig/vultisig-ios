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

    init(nodeAddress: String, provider: String = "", fee: Int64 = .zero) {
        self.nodeAddress = nodeAddress
        self.provider = provider
        self.fee = fee
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
            StyledFloatingPointField(placeholder: "Amount", value: Binding(
                get: { self.amount },
                set: { self.amount = $0 }
            ), format: .number)
            TransactionMemoAddressTextField(memo: self, addressKey: "nodeAddress")
            TransactionMemoAddressTextField(memo: self, addressKey: "provider")
            StyledIntegerField(placeholder: "Operator's Fee", value: Binding(
                get: { self.fee },
                set: { self.fee = $0 }
            ), format: .number)
        })
    }
}
