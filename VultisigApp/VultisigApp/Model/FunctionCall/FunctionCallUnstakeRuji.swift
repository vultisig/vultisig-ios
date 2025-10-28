//
//  FunctionCallUnstakeRuji.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/07/2025.
//

import SwiftUI
import Foundation
import Combine
import BigInt

class FunctionCallUnstakeRuji: ObservableObject {
    @Published var amount: Decimal = 0
    @Published var amountValid: Bool = false
    @Published var isTheFormValid: Bool = false
    @Published private var stakedAmount: Decimal = .zero
    @Published private var fetchingBalance = false
    
    let destinationAddress = RUJIStakingConstants.contract
    
    private var cancellables = Set<AnyCancellable>()
    private var tx: SendTransaction
    
    required init(tx: SendTransaction) {
        self.tx = tx
        setupValidation()
    }
    
    var balance: String {
        return "(\(NSLocalizedString("balance", comment: "")): \(balanceAmountText))"
    }
    
    var balanceAmountText: String {
        fetchingBalance ? NSLocalizedString("loadingWithEllipsis", comment: "") : "\(stakedAmount.formatForDisplay()) \(tx.coin.ticker.uppercased())"
    }
    
    var amountBigInt: BigInt {
        (amount * pow(10, tx.coin.decimals)).description.toBigInt(decimals: tx.coin.decimals)
    }
    
    private func setupValidation() {
        $amountValid
            .receive(on: DispatchQueue.main)
            .map { $0 && !self.amount.isZero && self.stakedAmount >= self.amount }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return "withdraw:\(self.tx.coin.contractAddress):\(amountBigInt.description)"
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
            { "account": { "withdraw": { "amount": "\(amountBigInt.description)" } } }
            """,
            coins: []
        )
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallUnstakeRujiView(viewModel: self))
    }
    
    func fetchStakedBalance() {
        fetchingBalance = true
        Task {
            let balance = (try? await ThorchainService.shared.fetchRujiStakeBalance(thorAddr: tx.coin.address, tokenSymbol: "RUJI"))?.stakeAmount
            guard let balance else { return }
            await MainActor.run {
                stakedAmount = balance.toDisplayDecimal(decimals: tx.coin.decimals)
                fetchingBalance = false
            }
        }
    }
}

private struct FunctionCallUnstakeRujiView: View {
    @ObservedObject var viewModel: FunctionCallUnstakeRuji
    
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
        }.onLoad(perform: viewModel.fetchStakedBalance)
    }
}
