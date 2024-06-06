//
//  TransactionMemoLeave.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoLeave: TransactionMemoAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = true
    
    @Published var nodeAddress: String = ""
    
    var addressFields: [String: String] {
        get {
            return ["nodeAddress": nodeAddress]
        }
        set {
            if let value = newValue["nodeAddress"] {
                nodeAddress = value
            }
        }
    }
    
    required init() {}
    
    init(nodeAddress: String) {
        self.nodeAddress = nodeAddress
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return "LEAVE:\(self.nodeAddress)"
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", self.nodeAddress)
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            TransactionMemoAddressTextField(memo: self, addressKey: "nodeAddress", isAddressValid: Binding(
                get: { self.isTheFormValid },
                set: { self.isTheFormValid = $0 }
            ))
        })
    }
}
