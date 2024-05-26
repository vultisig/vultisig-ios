//
//  TransactionMemoCustom.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 24/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoCustom: TransactionMemoAddressable, ObservableObject {
    @Published var amount: Double = 0.0
    @Published var custom: String = ""
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(custom: String) {
        self.custom = custom
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return self.custom
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
            ), format: .number)
            StyledTextField(placeholder: "Custom Memo", text: Binding(
                get: { self.custom },
                set: { self.custom = $0 }
            ))
        })
    }
}
