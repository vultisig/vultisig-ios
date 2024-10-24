//
//  TransactionMemoUnstake.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/10/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoUnstake: TransactionMemoAddressable, ObservableObject {
    @Published var amount: Double = 1
    @Published var nodeAddress: String = "Ef8t6cZkqFuHjJ_a_ydEK_tu3LHWRA4JZXRyewLY4j8FZ6B5"
    
    // Internal
    @Published var amountValid: Bool = true
    @Published var nodeAddressValid: Bool = true
    @Published var isTheFormValid: Bool = true
    
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
    
    required init() {
        setupValidation()
    }
    
    private func setupValidation() {
        Publishers.CombineLatest($amountValid, $nodeAddressValid)
            .map { $0 && $1 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return "w"
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("nodeAddress", self.nodeAddress)
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
            
            StyledFloatingPointField(placeholder: "Amount", value: Binding(
                get: { self.amount },
                set: { self.amount = $0 }
            ), format: .number, isValid: Binding(
                get: { self.amountValid },
                set: { self.amountValid = $0 }
            ))
        })
    }
}
