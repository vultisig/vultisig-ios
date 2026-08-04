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
    @Published private(set) var byteFee: String = .empty

    /// Whether the rate field holds a value the user chose, rather than the one
    /// the selected fee mode resolves to.
    ///
    /// This has to be tracked explicitly rather than inferred by comparing the
    /// field to the fetched rate: re-typing the same number is still a choice,
    /// and — worse — reopening the sheet with a rate already pinned would have
    /// the initial fetch overwrite the field and then read back as "unedited",
    /// silently dropping the pin on Save.
    ///
    /// Seeded true when the form arrives with a rate already pinned. Set by
    /// `setByteFee`, released by `selectMode` (choosing a priority is an
    /// explicit "follow the mode again").
    @Published private(set) var hasUserEditedByteFee: Bool = false

    /// The byte fee to pin, or `nil` to keep following the fee mode.
    ///
    /// Rejects anything that isn't a positive integer inside `Int64` — a zero or
    /// negative rate plans a fee-less transaction no node will relay, and the
    /// value ends up in WalletCore's `Int64` `byteFee`, where an out-of-range
    /// conversion traps the process rather than failing.
    var resolvedCustomByteFee: BigInt? {
        guard hasUserEditedByteFee,
              let entered = BigInt(byteFee, radix: 10),
              entered > .zero,
              entered <= BigInt(Int64.max) else {
            return nil
        }
        return entered
    }

    /// User edit of the rate field. Pins the value so a later rate fetch — a
    /// fee-mode change, or reopening the sheet — cannot replace it.
    func setByteFee(_ value: String) {
        guard value != byteFee else { return }
        byteFee = value
        hasUserEditedByteFee = true
    }

    /// Choosing a priority is an explicit "follow the mode", so it releases any
    /// pinned rate and lets the fetch refill the field.
    func selectMode(_ mode: FeeMode) {
        hasUserEditedByteFee = false
        selectedMode = mode
    }

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
        // Arriving with a rate already pinned means the user set it earlier; the
        // initial fetch must not overwrite it, and Save must keep it.
        self.hasUserEditedByteFee = customByteFee != nil
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
        let resolvedGasLimit: BigInt?
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
        } else {
            resolvedGasLimit = nil
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
            // Never replace a rate the user pinned — that is what silently
            // un-pinned it on Save.
            guard !hasUserEditedByteFee else { return }
            byteFee = fee.description
        }
    }
}
