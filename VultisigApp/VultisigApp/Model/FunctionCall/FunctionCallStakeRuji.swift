//
//  FunctionCallStakeRuji.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/07/2025.
//

import SwiftUI
import Foundation
import Combine

class FunctionCallStakeRuji: ObservableObject {
    @Published var amount: Decimal = 0
    
    // Internal
    @Published var amountValid: Bool = false
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil
    
    private var cancellables = Set<AnyCancellable>()
    
    private var tx: SendTransaction
    private let vault: Vault
    
    let destinationAddress = RUJIStakingConstants.contract
    
    required init(
        tx: SendTransaction,
        vault: Vault,
        functionCallViewModel: FunctionCallViewModel
    ) {
        self.tx = tx
        self.vault = vault
        self.amount = tx.coin.balanceDecimal
        setupValidation()
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.formatForDisplay()
        return "(\(NSLocalizedString("balance", comment: "")): \(balance) \(tx.coin.ticker.uppercased()))"
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
            .receive(on: DispatchQueue.main)
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
        return "bond:\(self.tx.coin.contractAddress):\(self.tx.amountInRaw.description)"
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("memo", self.toString())
        return dict
    }
    
    var wasmContractPayload: WasmExecuteContractPayload {
        WasmExecuteContractPayload(
            senderAddress: tx.coin.address,
            contractAddress: destinationAddress,
            executeMsg: """
            { "account": { "bond": {} } }
            """,
            coins: [CosmosCoin(
                amount: self.tx.amountInRaw.description,
                denom: tx.coin.contractAddress
            )]
        )
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallStakeRujiView(viewModel: self))
    }
}

private struct FunctionCallStakeRujiView: View {
    @ObservedObject var viewModel: FunctionCallStakeRuji
    
    var body: some View {
        VStack {
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
        }
    }
}
