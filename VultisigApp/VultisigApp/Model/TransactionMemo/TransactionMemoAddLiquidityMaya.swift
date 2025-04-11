//
//  TransactionMemoAddLiquidityMaya.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 17/05/24.
//

import Combine
import Foundation
import SwiftUI

class TransactionMemoAddLiquidityMaya: ObservableObject
{
    @Published var amount: Double = 0.0
    
    // Internal
    @Published var amountValid: Bool = false
    
    @Published var isTheFormValid: Bool = false

    private var cancellables = Set<AnyCancellable>()

    required init() {
        setupValidation()
    }
    
    private func setupValidation() {
        $amountValid
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }

    var description: String {
        return toString()
    }

    func toString() -> String {
        let memo =
            "pool+"
        return memo
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", self.toString())
        return dict
    }

    func getView() -> AnyView {
        AnyView(
            VStack {
                StyledFloatingPointField(
                    placeholder: "Amount",
                    value: Binding(
                        get: { self.amount },
                        set: { self.amount = $0 }
                    ),
                    format: .number,
                    isValid: Binding(
                        get: { self.amountValid },
                        set: { self.amountValid = $0 }
                    )
                )
            })
    }
}
