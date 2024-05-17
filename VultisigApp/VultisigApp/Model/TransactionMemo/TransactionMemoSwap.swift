//
//  TransactionMemoSwap.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoSwap: TransactionMemoAddressable, ObservableObject {
    @Published var asset: String = ""
    @Published var destinationAddress: String = ""
    @Published var limit: Double = 0.0
    @Published var interval: Int = 0
    @Published var quantity: Int = 0
    @Published var affiliate: String = ""
    @Published var fee: Double = 0.0
    
    var addressFields: [String: String] {
        get { ["destinationAddress": destinationAddress] }
        set { if let value = newValue["destinationAddress"] { destinationAddress = value } }
    }
    
    required init() {}
    
    init(asset: String, destinationAddress: String, limit: Double, interval: Int, quantity: Int, affiliate: String = "", fee: Double) {
        self.asset = asset
        self.destinationAddress = destinationAddress
        self.limit = limit
        self.interval = interval
        self.quantity = quantity
        self.affiliate = affiliate
        self.fee = fee
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "SWAP:\(self.asset):\(self.destinationAddress)"
        
        // Adding limit with default check
        if self.limit != 0.0 {
            memo += ":\(self.limit)"
        }
        
        // Adding interval and quantity with default check
        if self.interval != 0 || self.quantity != 0 {
            memo += "/\(self.interval)/\(self.quantity)"
        }
        
        // Adding affiliate and fee with default check
        if !self.affiliate.isEmpty {
            memo += ":\(self.affiliate)"
            if self.fee != 0.0 {
                memo += ":\(self.fee)"
            }
        } else if self.fee != 0.0 {
            memo += "::\(self.fee)"
        }
        
        return memo
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("asset", "\(self.asset)")
        dict.set("destinationAddress", "\(self.destinationAddress)")
        dict.set("limit", "\(self.limit)")
        dict.set("interval", "\(self.interval)")
        dict.set("quantity", "\(self.quantity)")
        dict.set("affiliate", "\(self.affiliate)")
        dict.set("fee", "\(self.fee)")
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledTextField(placeholder: "Asset", text: Binding(
                get: { self.asset },
                set: { self.asset = $0 }
            ))
            TransactionMemoAddressTextField(memo: self, addressKey: "destinationAddress")
            StyledFloatingPointField(placeholder: "Limit", value: Binding(
                get: { self.limit },
                set: { self.limit = $0 }
            ), format: .number)
            StyledIntegerField(placeholder:"Interval", value: Binding(
                get: { self.interval },
                set: { self.interval = $0 }
            ), format: .number)
            StyledIntegerField(placeholder:"Quantity", value: Binding(
                get: { self.quantity },
                set: { self.quantity = $0 }
            ), format: .number)
            StyledTextField(placeholder:"Affiliate", text: Binding(
                get: { self.affiliate },
                set: { self.affiliate = $0 }
            ))
            StyledFloatingPointField(placeholder:"Fee", value: Binding(
                get: { self.fee },
                set: { self.fee = $0 }
            ), format: .number)
        })
    }
}
