//
//  FunctionCallUnstakeTCY.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/05/2025.

import SwiftUI
import Foundation
import Combine

class FunctionCallUnstakeTCY: ObservableObject {
    @Published var amount: String = ""
    public var lastUpdateTime: Date = Date()
    
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
        $amount
            .sink { [weak self] _ in
                self?.validateAmount()
            }
            .store(in: &cancellables)
        
        $amountValid
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        if let intAmount = Int64(self.amount) {
            let basisPoints = intAmount * 100
            return "tcy-:\(basisPoints)"
        } else {
            return "tcy-:0"
        }
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", self.toString())
        return dict
    }
    
    var percentageButtons: some View {
        PercentageButtons { [weak self] percentage in
            self?.setPercentage(percentage)
        }
    }
    
    func setPercentage(_ percentage: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.amount = String(percentage)
            self.validateAmount()
            self.lastUpdateTime = Date()
            self.objectWillChange.send()
        }
    }
    
    func getView() -> AnyView {
        return AnyView(UnstakeView(viewModel: self))
    }
    
    func validateAmount() {
        if let intAmount = Int64(amount), intAmount > 0 {
            amountValid = true
        } else {
            amountValid = false
        }
        
        isTheFormValid = amountValid
    }
    
    
    
    struct PercentageButtons: View {
        let action: (Int) -> Void
        
        var body: some View {
            HStack(spacing: 8) {
                ForEach([25, 50, 75, 100], id: \.self) { option in
                    Button(action: {
                        action(option)
                    }) {
                        Text("\(option)%")
                            .font(.body12BrockmannMedium)
                            .foregroundColor(.neutral0)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue600)
                            .cornerRadius(32)
                    }
                }
            }
        }
    }
}

struct UnstakeView: View {
    @ObservedObject var viewModel: FunctionCallUnstakeTCY
    
    var textField: some View {
        TextField("Enter percentage", text: $viewModel.amount)
            .id(viewModel.lastUpdateTime)
        //.keyboardType(.numberPad)
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
            .padding(12)
            .background(Color.blue600)
            .cornerRadius(12)
            .borderlessTextFieldStyle()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                viewModel.percentageButtons
                
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.blue400)
            }
            .frame(maxWidth: .infinity)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Percentage to Unstake \(viewModel.balance)")
                        .font(.body14MontserratMedium)
                        .foregroundColor(.neutral0)
                    if !viewModel.amountValid {
                        Text("*")
                            .font(.body14MontserratMedium)
                            .foregroundColor(.red)
                    }
                }
                
#if os(iOS)
                textField.keyboardType(.decimalPad)
#endif
#if os(macOS)
                textField
#endif
            }
        }
    }
}
