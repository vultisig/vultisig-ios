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
    @Published var isAutoCompound: Bool = false
    public var lastUpdateTime: Date = Date()
    
    @Published var amountValid: Bool = false
    @Published var isTheFormValid: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private var tx: SendTransaction
    private let vault: Vault
    
    private var stakedAmount: Decimal = .zero
    private var autoCompoundAmount: Decimal = .zero
    
    let destinationAddress = TCYAutoCompoundConstants.contract
    
    required init(
        tx: SendTransaction, vault: Vault, functionCallViewModel: FunctionCallViewModel, stakedAmount: Decimal
    ) {
        self.stakedAmount = stakedAmount
        self.tx = tx
        self.vault = vault
        setupValidation()
    }
    
    var balance: String {
        if isAutoCompound {
            return "( Auto-Compound Amount: \(self.autoCompoundAmount) \(tx.coin.ticker.uppercased()) )"
        } else {
            return "( Staked Amount: \(self.stakedAmount) \(tx.coin.ticker.uppercased()) )"
        }
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
        if isAutoCompound {
            if let intAmount = Int64(self.amount) {
                let basisPoints = intAmount * 100
                let withdrawAmount = (autoCompoundAmount * Decimal(intAmount)) / 100
                return "bond:\(self.tx.coin.contractAddress):\(withdrawAmount.toInt())"
            } else {
                return "bond:\(self.tx.coin.contractAddress):0"
            }
        } else {
            if let intAmount = Int64(self.amount) {
                let basisPoints = intAmount * 100
                return "tcy-:\(basisPoints)"
            } else {
                return "tcy-:0"
            }
        }
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", self.toString())
        return dict
    }
    
    var wasmContractPayload: WasmExecuteContractPayload? {
        guard isAutoCompound else { return nil }
        
        if let intAmount = Int64(self.amount) {
            let basisPoints = intAmount * 100
            let withdrawAmount = (autoCompoundAmount * Decimal(intAmount)) / 100
            
            return WasmExecuteContractPayload(
                senderAddress: tx.coin.address,
                contractAddress: destinationAddress,
                executeMsg: """
                { "withdraw": { "amount": "\(withdrawAmount.toInt())" } }
                """,
                coins: []
            )
        }
        return nil
    }
    
    func fetchAutoCompoundBalance() {
        Task {
            let amount = await ThorchainService.shared.fetchTcyAutoCompoundAmount(address: tx.coin.address)
            await MainActor.run {
                autoCompoundAmount = amount
                validateAmount() // Revalidate after fetching balance
            }
        }
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
            let relevantAmount = isAutoCompound ? autoCompoundAmount : stakedAmount
            if relevantAmount > 0 {
                amountValid = true
            } else {
                amountValid = false
            }
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
                            .font(Theme.fonts.caption12)
                            .foregroundColor(Theme.colors.textPrimary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Theme.colors.bgSecondary)
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
            .font(Theme.fonts.bodyMRegular)
            .foregroundColor(Theme.colors.textPrimary)
            .padding(12)
            .background(Theme.colors.bgSecondary)
            .cornerRadius(12)
            .borderlessTextFieldStyle()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Toggle(isOn: $viewModel.isAutoCompound) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unstake Auto-Compound TCY")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(Theme.colors.textPrimary)
                    Text("Unstake from auto-compounding TCY deposits")
                        .font(Theme.fonts.caption12)
                        .foregroundColor(Theme.colors.textPrimary)
                }
            }
            .toggleStyle(SwitchToggleStyle())
            .onChange(of: viewModel.isAutoCompound) { newValue in
                if newValue {
                    viewModel.fetchAutoCompoundBalance()
                }
            }
            
            VStack(spacing: 8) {
                viewModel.percentageButtons
                
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Theme.colors.bgTertiary)
            }
            .frame(maxWidth: .infinity)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Percentage to Unstake \(viewModel.balance)")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(Theme.colors.textPrimary)
                    if !viewModel.amountValid {
                        Text("*")
                            .font(Theme.fonts.bodySMedium)
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
