//
//  FunctionCallStakeTCY.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/05/2025.

import SwiftUI
import Foundation
import Combine

class FunctionCallStakeTCY: ObservableObject {
    @Published var amount: Decimal = 0
    
    // Internal
    @Published var amountValid: Bool = false
    @Published var isTheFormValid: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private var tx: SendTransaction
    
    required init(
        tx: SendTransaction, functionCallViewModel: FunctionCallViewModel
    ) {
        self.tx = tx
        self.amount = tx.coin.balanceDecimal
        setupValidation()
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.formatDecimalToLocale()
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }
    
    private func setupValidation() {
        $amountValid
            .map { $0 && !self.amount.isZero && self.tx.coin.balanceDecimal >= self.amount }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return "tcy+"
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", self.toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            StyledFloatingPointField(
                placeholder: Binding(
                    get: { "Amount \(self.balance)" },
                    set: { _ in }
                ),
                value: Binding(
                    get: { self.amount },
                    set: { self.amount = $0 }
                ),
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                ))
        })
    }
}
