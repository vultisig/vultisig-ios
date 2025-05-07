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
    @Published var amountValid: Bool = true
    @Published var isTheFormValid: Bool = true
    
    private var cancellables = Set<AnyCancellable>()
    
    private var tx: SendTransaction
    
    required init(
        tx: SendTransaction, functionCallViewModel: FunctionCallViewModel
    ) {
        self.tx = tx
        setupValidation()
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.formatDecimalToLocale()
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
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
    
    // API call to fetch staked amount
    func fetchStakedAmount() {
        let address = tx.coin.address
        Task {
            if let url = URL(string: "https://thornode.ninerealms.com/thorchain/tcy_staker/\(address)") {
                let (data, _) = try await URLSession.shared.data(from: url)
                // Process data to update stakedAmount
            }
        }
    }
    
    var percentageButtons: some View {
        SwapPercentageButtons { percentage in
            print(percentage)
        }
    }
    
    func getView() -> AnyView {
        AnyView(VStack {
            percentageButtons
            StyledIntegerField(
                placeholder: "Amount \(self.balance)",
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
