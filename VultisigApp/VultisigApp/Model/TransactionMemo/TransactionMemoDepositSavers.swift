//
//  TransactionMemoDepositSavers.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoDepositSavers: TransactionMemoAddressable, ObservableObject {
    @Published var pool: String = ""
    @Published var affiliate: String = ""
    @Published var fee: Double = 0.0
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(pool: String, affiliate: String = "", fee: Double = 0.0) {
        self.pool = pool
        self.affiliate = affiliate
        self.fee = fee
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "DEPOSIT:\(self.pool)"
        
        if !self.affiliate.isEmpty {
            memo += ":\(self.affiliate)"
        }
        
        if self.fee != 0.0 {
            if self.affiliate.isEmpty {
                memo += "::\(self.fee)"
            } else {
                memo += ":\(self.fee)"
            }
        }
        
        return memo
    }
    
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("pool", "\(self.pool)")
        dict.set("affiliate", "\(self.affiliate)")
        dict.set("fee", "\(self.fee)")
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Pool", text: Binding(
                get: { self.pool },
                set: { self.pool = $0 }
            ))
            StyledTextField(placeholder: "Affiliate", text: Binding(
                get: { self.affiliate },
                set: { self.affiliate = $0 }
            ))
            StyledFloatingPointField(placeholder: "Fee", value: Binding(
                get: { self.fee },
                set: { self.fee = $0 }
            ), format: .number)
        })
    }
}
