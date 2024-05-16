//
//  TransactionMemoRepayLoan.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoRepayLoan: TransactionMemoAddressable, ObservableObject {
    @Published var asset: String = ""
    @Published var destinationAddress: String = ""
    @Published var minOut: Double = 0.0
    
    var addressFields: [String: String] {
        get { ["destinationAddress": destinationAddress] }
        set { if let value = newValue["destinationAddress"] { destinationAddress = value } }
    }
    
    required init() {}
    
    init(asset: String, destinationAddress: String, minOut: Double) {
        self.asset = asset
        self.destinationAddress = destinationAddress
        self.minOut = minOut
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        "LOAN-:\(self.asset):\(self.destinationAddress):\(self.minOut)"
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Asset", text: Binding(
                get: { self.asset },
                set: { self.asset = $0 }
            ))
            TransactionMemoAddressTextField(memo: self, addressKey: "destinationAddress")
            StyledFloatingPointField(placeholder: "Min Out", value: Binding(
                get: { self.minOut },
                set: { self.minOut = $0 }
            ), format: .number)
        })
    }
}
