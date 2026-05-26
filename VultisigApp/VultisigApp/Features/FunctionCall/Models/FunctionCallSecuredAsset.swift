//
//  FunctionCallSecuredAsset.swift
//  VultisigApp
//
//  SECURE+ mint sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — drops `FunctionCallAddressable` and
//  `getView() -> AnyView`. Holds an internal `tx: FunctionCallForm`
//  scratchpad for the inbound-address / ERC20 approval plumbing.
//  Cross-mutator per the addendum — its chain-dependent THORChain-vs-EVM
//  branching reads the screen-owned coin via `@Binding`.
//

import BigInt
import Combine
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "function-call-secured-asset")

@Observable
@MainActor
final class FunctionCallSecuredAsset {
    var amount: Decimal = 0.0
    var thorAddress: String = ""

    var isApprovalRequired: Bool = false
    var approvePayload: ERC20ApprovePayload?
    var customErrorMessage: String?

    /// Internal scratchpad — see `FunctionCallAddThorLP` for the
    /// rationale.
    let tx: FunctionCallForm

    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private var loadingTasks: [Task<Void, Never>] = []

    init(tx: FunctionCallForm, vault: Vault) {
        self.tx = tx
        self.vault = vault
    }

    deinit {
        loadingTasks.forEach { $0.cancel() }
    }

    func initialize() {
        prefillAddresses()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.fetchInboundAddressAndSetupApproval()
        }
        loadingTasks.append(task)
        updateErrorMessage()
    }

    private func prefillAddresses() {
        if let thorCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
            thorAddress = thorCoin.address
        }
    }

    private func fetchInboundAddressAndSetupApproval() async {
        let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()

        if tx.coin.chain == .thorChain {
            tx.toAddress = tx.coin.address
            isApprovalRequired = false
            approvePayload = nil
            return
        }

        let chainName = ThorchainService.getInboundChainName(for: tx.coin.chain)
        guard let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
            return
        }

        if inbound.halted || inbound.global_trading_paused || inbound.chain_trading_paused || inbound.chain_lp_actions_paused {
            customErrorMessage = String(format: "inboundPaused".localized, inbound.chain)
            return
        }

        let destinationAddress: String
        if tx.coin.shouldApprove {
            guard let router = inbound.router, !router.isEmpty else {
                customErrorMessage = String(format: "routerNotAvailable".localized, inbound.chain)
                isApprovalRequired = false
                return
            }
            destinationAddress = router
        } else {
            destinationAddress = inbound.address
        }

        tx.toAddress = destinationAddress
        isApprovalRequired = tx.coin.shouldApprove
        if isApprovalRequired {
            approvePayload = tx.toAddress.isEmpty ? nil : ERC20ApprovePayload(
                amount: tx.amountInRaw,
                spender: tx.toAddress
            )
        }
    }

    func isAmountValid(against coin: Coin) -> Bool {
        amount > 0 && amount <= coin.balanceDecimal
    }

    func validate(against coin: Coin) {
        updateErrorMessage(against: coin)
    }

    var isTheFormValid: Bool {
        let amountValid = isAmountValid(against: tx.coin)
        let thorValid = !thorAddress.isEmpty
        return amountValid && thorValid && !amount.isZero
    }

    private func updateErrorMessage(against coin: Coin? = nil) {
        var errors: [String] = []
        let targetCoin = coin ?? tx.coin

        if thorAddress.isEmpty {
            errors.append("thorAddressNotFound".localized)
        }
        if amount <= 0 {
            errors.append("enterValidAmount".localized)
        } else if targetCoin.balanceDecimal < amount {
            errors.append("insufficientBalanceForFunctions".localized)
        }

        if errors.isEmpty {
            customErrorMessage = nil
        } else {
            customErrorMessage = errors.joined(separator: "\n")
        }
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        "SECURE+:\(thorAddress)"
    }

    var balance: String {
        let b = tx.coin.balanceDecimal.formatForDisplay()
        return "( Balance: \(b) \(tx.coin.ticker.uppercased()) )"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("operation", "mint")
        dict.set("memo", toString())
        dict.set("amount", amount.description)
        dict.set("thorAddress", thorAddress)
        return dict
    }

    func buildApprovePayload() -> ERC20ApprovePayload? {
        guard isApprovalRequired, !tx.toAddress.isEmpty else { return nil }
        return ERC20ApprovePayload(amount: tx.amountInRaw, spender: tx.toAddress)
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        _ = isFastVault
        tx.amount = amount.formatToDecimal(digits: coin.decimals)
        return SendTransaction.empty(coin: coin, vault: vault).copy(
            toAddress: tx.toAddress.isEmpty ? "" : tx.toAddress,
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: toDictionary().allItems(),
            wasmContractPayload: .set(nil)
        )
    }
}

struct SecuredAssetFormView: View {
    @Bindable var model: FunctionCallSecuredAsset
    @Binding var selectedCoin: Coin

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("mintSecuredAsset".localized)
                    .font(.headline)
                Text(String(format: "targetAsset".localized, "\(model.tx.coin.chain.swapAsset)-\(model.tx.coin.ticker)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if model.isApprovalRequired {
                approvalInfo
            }

            VStack(alignment: .leading, spacing: 8) {
                StyledFloatingPointField(
                    label: "amount".localized,
                    placeholder: "enterAmount".localized,
                    value: $model.amount,
                    isValid: .constant(true)
                )
                .onChange(of: model.amount) {
                    model.validate(against: selectedCoin)
                }

                Text(model.balance)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage = model.customErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !model.thorAddress.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("thorAddressAutoFilled".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.thorAddress)
                        .font(.footnote)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("generatedMemo".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.toString())
                    .font(.footnote)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .onAppear {
            model.initialize()
        }
    }

    private var approvalInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("erc20ApprovalRequired".localized)
                .font(.headline)
                .foregroundStyle(.primary)

            Text("erc20ApprovalRequiredMessage".localized)
                .font(.body)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text("approvalTransaction".localized)
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("mintTransaction".localized)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .padding(.leading, 16)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
}
