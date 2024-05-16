//
//  TransactionMemoNodeMaintenance.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoNodeMaintenance: TransactionMemoAddressable, ObservableObject {
    @Published var nodeAddress: String = ""
    @Published var provider: String = ""
    @Published var fee: Double = 0.0
    @Published var amount: Double = 0.0
    @Published var action: NodeAction = .bond
    
    enum NodeAction: String, CaseIterable, Identifiable {
        case bond, unbond, leave
        var id: String { self.rawValue }
    }
    
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
    
    init(nodeAddress: String, provider: String = "", fee: Double = 0.0, amount: Double = 0.0, action: NodeAction = .bond) {
        self.nodeAddress = nodeAddress
        self.provider = provider
        self.fee = fee
        self.amount = amount
        self.action = action
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = ""
        switch self.action {
        case .bond:
            memo = "BOND:\(self.nodeAddress)"
        case .unbond:
            memo = "UNBOND:\(self.nodeAddress):\(self.amount)"
        case .leave:
            memo = "LEAVE:\(self.nodeAddress)"
        }
        if !self.provider.isEmpty && self.fee != 0.0 {
            memo += ":\(provider):\(fee)"
        }
        return memo
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            TransactionMemoAddressTextField(memo: self, addressKey: "nodeAddress")
            TransactionMemoAddressTextField(memo: self, addressKey: "provider")
            StyledFloatingPointField(placeholder: "Fee", value: Binding(
                get: { self.fee },
                set: { self.fee = $0 }
            ), format: .number)
            StyledFloatingPointField(placeholder: "Amount", value: Binding(
                get: { self.amount },
                set: { self.amount = $0 }
            ), format: .number)
            Picker("Action", selection: Binding(
                get: { self.action },
                set: { self.action = $0 }
            )) {
                Text("Bond").tag(NodeAction.bond)
                Text("Unbond").tag(NodeAction.unbond)
                Text("Leave").tag(NodeAction.leave)
            }
        })
    }
}
