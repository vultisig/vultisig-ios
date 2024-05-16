//
//  TransactionMemoWithdrawLiquidity.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 15/05/24.
//

import SwiftUI
import Foundation
import Combine

class TransactionMemoWithdrawLiquidity: TransactionMemoAddressable, ObservableObject {
    @Published var pool: String = ""
    @Published var basisPoints: Int = 0
    @Published var asset: String = ""
    
    var addressFields: [String: String] {
        get { [:] }
        set { }
    }
    
    required init() {}
    
    init(pool: String, basisPoints: Int, asset: String = "") {
        self.pool = pool
        self.basisPoints = basisPoints
        self.asset = asset
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        var memo = "WITHDRAW:\(self.pool):\(self.basisPoints)"
        if !self.asset.isEmpty {
            memo += ":\(asset)"
        }
        return memo
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
            StyledTextField(placeholder: "Asset", text: Binding(
                get: { self.asset },
                set: { self.asset = $0 }
            ))
        })
    }
}
