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
    @Published var isAutoCompound: Bool = false

    @Published var amountValid: Bool = false
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil
    
    private var cancellables = Set<AnyCancellable>()
    
    private var tx: SendTransaction
    private let vault: Vault
    
    let destinationAddress = TCYAutoCompoundConstants.contract
    
    required init(
        tx: SendTransaction, vault: Vault
    ) {
        self.tx = tx
        self.vault = vault
        self.amount = tx.coin.balanceDecimal
    }
    
    func initialize() {
        // Ensure TCY token is selected for TCY staking operations on THORChain
        DispatchQueue.main.async {
            if let tcyCoin = self.vault.tcyCoin {
                self.tx.coin = tcyCoin
            }
        }
        setupValidation()
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.formatForDisplay()
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }
    
    private func setupValidation() {
        $amount
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] newAmount in
                self?.validateAmount()
            }
            .store(in: &cancellables)
        
        $amountValid
            .map { $0 && !self.amount.isZero && self.tx.coin.balanceDecimal >= self.amount }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    private func validateAmount() {
        let balance = tx.coin.balanceDecimal
        let isValidAmount = amount > 0 && amount <= balance
        amountValid = isValidAmount
        
        if balance < amount {
            amountValid = false
            self.customErrorMessage = NSLocalizedString("insufficientBalanceForFunctions", comment: "Error message when user tries to enter amount greater than available balance")
        } else {
            self.customErrorMessage = nil
        }
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
    
    var wasmContractPayload: WasmExecuteContractPayload? {
        guard isAutoCompound else { return nil }
        
        return WasmExecuteContractPayload(
            senderAddress: tx.coin.address,
            contractAddress: destinationAddress,
            executeMsg: """
            { "liquid": { "bond": {} } }
            """,
            coins: [CosmosCoin(
                amount: self.tx.amountInRaw.description,
                denom: tx.coin.contractAddress
            )]
        )
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallStakeTCYView(viewModel: self))
    }
}

private struct FunctionCallStakeTCYView: View {
    @ObservedObject var viewModel: FunctionCallStakeTCY
    
    var body: some View {
        VStack(spacing: 16) {
            StyledFloatingPointField(
                label: "\(NSLocalizedString("amount", comment: "")) \(viewModel.balance)",
                placeholder: NSLocalizedString("enterAmount", comment: ""),
                value: Binding(
                    get: { viewModel.amount },
                    set: { viewModel.amount = $0 }
                ),
                isValid: Binding(
                    get: { viewModel.amountValid },
                    set: { viewModel.amountValid = $0 }
                ))
            
            Toggle(isOn: $viewModel.isAutoCompound) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("enableAutoCompounding", comment: ""))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(Theme.colors.textPrimary)
                    Text(NSLocalizedString("automaticallyCompoundTCYRewards", comment: ""))
                        .font(Theme.fonts.caption12)
                        .foregroundColor(Theme.colors.textPrimary)
                }
            }
            .toggleStyle(.switch)
        }
        .onAppear {
            viewModel.initialize()
        }
    }
}
