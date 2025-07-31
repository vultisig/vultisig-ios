//
//  FunctionCallWithdrawRujiRewards.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 31/07/2025.
//

import SwiftUI
import Foundation
import Combine
import BigInt

class FunctionCallWithdrawRujiRewards: ObservableObject {
    @Published var amount: Decimal = 0
    @Published var amountValid: Bool = false
    @Published var isTheFormValid: Bool = false
    @Published private var rewardsAmount: Decimal = .zero
    @Published private var rewardsTicker: String = ""
    @Published private var fetchingBalance = false

    let destinationAddress = RUJIStakingConstants.contract
    
    private var cancellables = Set<AnyCancellable>()
    private var tx: SendTransaction
    
    required init(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel) {
        self.tx = tx
        setupValidation()
    }
    
    var balance: String {
        return "(\(NSLocalizedString("balance", comment: "")): \(balanceAmountText)"
    }
    
    var balanceAmountText: String {
        fetchingBalance ? NSLocalizedString("loadingWithEllipsis", comment: "") : "\(rewardsAmount.formatForDisplay()) \(rewardsTicker)"
    }
    
    var amountBigInt: BigInt {
        (amount * pow(10, tx.coin.decimals)).description.toBigInt(decimals: tx.coin.decimals)
    }
    
    private func setupValidation() {
        $amountValid
            .receive(on: DispatchQueue.main)
            .map { $0 && !self.amount.isZero && self.rewardsAmount >= self.amount }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return "claim:\(self.tx.coin.contractAddress):\(amountBigInt.description)"
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
            { "account": { "claim": {} } }
            """,
            coins: []
        )
    }
    func getView() -> AnyView {
        AnyView(FunctionCallWithdrawRujiRewardsView(viewModel: self))
    }
    
    func fetchStakedBalance() {
        fetchingBalance = true
        Task {
            let balances = (try? await ThorchainService.shared.fetchRujiStakeBalance(thorAddr: tx.coin.address, tokenSymbol: "RUJI"))
            guard let balances else { return }
            await MainActor.run {
                rewardsAmount = balances.rewardsAmount.toDisplayDecimal(decimals: tx.coin.decimals)
                rewardsTicker = balances.rewardsTicker
                fetchingBalance = false
            }
        }
    }
}

private struct FunctionCallWithdrawRujiRewardsView: View {
    @ObservedObject var viewModel: FunctionCallWithdrawRujiRewards
    
    var body: some View {
        VStack {
            StyledFloatingPointField(
                label: "\(NSLocalizedString("pendingRewards", comment: "")) \(viewModel.balance)",
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
