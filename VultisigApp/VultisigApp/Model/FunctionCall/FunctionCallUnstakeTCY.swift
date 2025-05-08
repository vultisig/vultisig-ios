//
//  FunctionCallUnstakeTCY.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/05/2025.

import SwiftUI
import Foundation
import Combine

class FunctionCallUnstakeTCY: ObservableObject {
    @Published var amount: Int64 = .zero
    
    // Internal
    @Published var amountValid: Bool = false
    @Published var isTheFormValid: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private var tx: SendTransaction
    
    private var stakedAmount: Decimal = .zero
    
    required init(
        tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, stakedAmount: Decimal
    ) {
        self.stakedAmount = stakedAmount
        self.tx = tx
        setupValidation()
    }
    
    var balance: String {
        return "( Staked Amount: \(self.stakedAmount) \(tx.coin.ticker.uppercased()) )"
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
        let basisPoints = self.amount * 100  // Convert to basis points (25% -> 2500)
        return "tcy-:\(basisPoints)"
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", self.toString())
        return dict
    }
    
    var percentageButtons: some View {
        SwapPercentageButtons { percentage in
            self.amount = Int64(percentage)
        }
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            percentageButtons
            StyledIntegerField(
                placeholder: "Percentage to Unstake \(self.balance)",
                value: Binding(
                    get: { self.amount },
                    set: { self.amount = $0 }
                ),
                format: .number,
                isValid: Binding(
                    get: { self.amountValid },
                    set: { self.amountValid = $0 }
                ))
        })
    }
}
