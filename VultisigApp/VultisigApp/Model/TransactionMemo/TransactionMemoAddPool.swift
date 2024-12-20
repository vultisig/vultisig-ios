//
//  TransactionMemoPool.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 12/08/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoAddPool: TransactionMemoAddressable, ObservableObject {
    @Published var amount: Double = 0
    
    // Internal
    @Published var amountValid: Bool = false
    
    @Published var isTheFormValid: Bool = false
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {
        setupValidation()
    }
    
    private func setupValidation() {
        self.isTheFormValid = true
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return "POOL+"
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
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
