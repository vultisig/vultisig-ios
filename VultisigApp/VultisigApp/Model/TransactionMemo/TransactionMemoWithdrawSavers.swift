//
//  TransactionMemoWithdrawSavers.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoWithdrawSavers: TransactionMemoAddressable, ObservableObject {
    @Published var pool: String = ""
    @Published var basisPoints: Int = 0
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(pool: String, basisPoints: Int) {
        self.pool = pool
        self.basisPoints = basisPoints
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return "WITHDRAW:\(self.pool):\(self.basisPoints)"
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("pool", "\(self.pool)")
        dict.set("basisPoints", "\(self.basisPoints)")
        dict.set("string_value", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Pool", text: Binding(
                get: { self.pool },
                set: { self.pool = $0 }
            ))
            StyledIntegerField(placeholder: "Basis Points", value: Binding(
                get: { self.basisPoints },
                set: { self.basisPoints = $0 }
            ), format: .number)
        })
    }
}
