//
//  TransactionMemoDonateReserve.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoDonateReserve: TransactionMemoAddressable, ObservableObject {
    @Published var pool: String = ""
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(pool: String = "") {
        self.pool = pool
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        guard !self.pool.isEmpty else {
            return "RESERVE"
        }
        return "DONATE:\(pool)"
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("pool", "\(self.pool)")
        dict.set("string_value", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Pool", text: Binding(
                get: { self.pool },
                set: { self.pool = $0 }
            ))
        })
    }
}
