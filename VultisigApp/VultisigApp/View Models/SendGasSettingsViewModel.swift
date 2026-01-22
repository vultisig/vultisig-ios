//
//  SendGasSettingsViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 28.08.2024.
//

import Foundation
import BigInt

final class SendGasSettingsViewModel: ObservableObject {

    private let coin: Coin
    private let vault: Vault

    @Published var selectedMode: FeeMode = .default

    // EVM
    @Published var gasLimit: String = .empty
    @Published var baseFee: String = .empty
    @Published var priorityFeesMap: [FeeMode: BigInt] = [:]

    // UTXO
    @Published var byteFee: String = .empty

    init(coin: Coin, vault: Vault, gasLimit: String, byteFee: String, baseFee: String, selectedMode: FeeMode) {
        self.coin = coin
        self.vault = vault
        self.gasLimit = gasLimit
        self.byteFee = byteFee
        self.baseFee = baseFee
        self.selectedMode = selectedMode
    }

    init(coin: Coin, vault: Vault, gasLimit: BigInt, customByteFee: BigInt?, selectedMode: FeeMode) {
        self.coin = coin
        self.vault = vault
        self.gasLimit = gasLimit.description
        self.byteFee = customByteFee?.description ?? .empty
        self.baseFee = baseFee.description
        self.selectedMode = selectedMode
    }

    var chain: Chain {
        return coin.chain
    }

    var totalFee: String {
        let gasLimit = Decimal(string: gasLimit) ?? .zero
        let baseFeeGwei = Decimal(string: baseFee) ?? .zero
        let baseFeeWei = baseFeeGwei * Decimal(EVMHelper.weiPerGWei)
        let baseFeeWeiValue = BigInt(stringLiteral: baseFeeWei.description)
        let normalizedBaseFeeWei = BlockChainService.normalizeEVMFee(baseFeeWeiValue)
        let priorityFee = Decimal(priorityFeesMap[selectedMode] ?? .zero)
        let totalFee = gasLimit * (Decimal(normalizedBaseFeeWei) + priorityFee)
        let totalFeeGwei = totalFee / Decimal(EVMHelper.weiPerGWei)
        return totalFeeGwei.description
    }

    var totalFeeFiat: String {
        guard let nativeCoin = vault.nativeCoin(for: coin) else { return .zero }
        let totalFeeGwei = Decimal(string: totalFee) ?? .zero
        let totalFeeWei = totalFeeGwei * Decimal(EVMHelper.weiPerGWei)
        let totalFee = nativeCoin.decimal(for: BigInt(stringLiteral: totalFeeWei.description))
        return RateProvider.shared.fiatBalanceString(value: totalFee, coin: nativeCoin)
    }

    func fetch(chain: Chain) async throws {
        switch chain.chainType {
        case .UTXO:
            try await fetchUTXO()
        case .EVM:
            try await fetchEVM()
        default:
            break
        }
    }
}

private extension SendGasSettingsViewModel {

    func fetchEVM() async throws {
        let service = try EvmService.getService(forChain: chain)
        async let baseFeeWeiTask = service.getBaseFee()
        async let tmpFeeMapTask =  service.fetchMaxPriorityFeesPerGas()
        let (baseFeeWei, tmpFeeMap) = try await (baseFeeWeiTask, tmpFeeMapTask)
        let baseFeeGwei = Decimal(baseFeeWei) / Decimal(EVMHelper.weiPerGWei)
        await MainActor.run {
            baseFee = baseFeeGwei.description
            priorityFeesMap = tmpFeeMap
        }
    }

    func fetchUTXO() async throws {
        let service = BlockChainService.shared
        let fee =  try await service.fetchUTXOFee(
            coin: coin,
            feeMode: selectedMode
        )
        await MainActor.run {
            byteFee = fee.description
        }
    }
}
