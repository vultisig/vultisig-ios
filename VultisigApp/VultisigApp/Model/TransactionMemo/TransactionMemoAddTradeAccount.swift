//
//  TransactionMemoAddTradeAccount.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoAddTradeAccount: TransactionMemoAddressable, ObservableObject {
    @Published var address: String = ""
    
    var addressFields: [String: String] {
        get { ["address": address] }
        set { if let value = newValue["address"] { address = value } }
    }
    
    required init() {}
    
    init(address: String) {
        self.address = address
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        "TRADE+:\(self.address)"
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            TransactionMemoAddressTextField(memo: self, addressKey: "address")
        })
    }
}
