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

    // Send context used to estimate the EVM gas limit against the real
    // recipient when the user hasn't pinned a custom one.
    private let fromAddress: String
    private let toAddress: String
    private let amount: BigInt
    private let memo: String?
    private let customGasLimit: BigInt?

    // Estimate the gas limit only on the first fetch. `fetch()` also fires on
    // every priority-mode change, and re-running would clobber a manual edit to
    // the Gas Limit field.
    private var hasEstimatedGasLimit = false

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
        self.fromAddress = .empty
        self.toAddress = .empty
        self.amount = .zero
        self.memo = nil
        self.customGasLimit = nil
        self.gasLimit = gasLimit
        self.byteFee = byteFee
        self.baseFee = baseFee
        self.selectedMode = selectedMode
    }

    init(
        coin: Coin,
        vault: Vault,
        gasLimit: BigInt,
        customGasLimit: BigInt?,
        customByteFee: BigInt?,
        selectedMode: FeeMode,
        fromAddress: String,
        toAddress: String,
        amount: BigInt,
        memo: String?
    ) {
        self.coin = coin
        self.vault = vault
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.amount = amount
        self.memo = memo
        self.customGasLimit = customGasLimit
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

        // Seed the editable Gas Limit with the real `eth_estimateGas` result
        // (padded/floored), so the field and the Total Fee reflect the estimate
        // instead of the flat default. Skipped when the user has pinned a custom
        // limit — their value must win.
        var resolvedGasLimit: BigInt?
        if customGasLimit == nil, !fromAddress.isEmpty, !hasEstimatedGasLimit {
            resolvedGasLimit = await BlockChainService.shared.resolveEVMSendGasLimit(
                coin: coin,
                fromAddress: fromAddress,
                toAddress: toAddress,
                amount: amount,
                memo: memo,
                requestedGasLimit: nil,
                customGasLimit: nil
            )
        }

        await MainActor.run {
            baseFee = baseFeeGwei.description
            priorityFeesMap = tmpFeeMap
            if let resolvedGasLimit {
                gasLimit = resolvedGasLimit.description
                hasEstimatedGasLimit = true
            }
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
