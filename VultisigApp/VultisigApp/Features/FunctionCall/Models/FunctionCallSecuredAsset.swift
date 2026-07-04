//
//  FunctionCallSecuredAsset.swift
//  VultisigApp
//
//  SECURE+ mint sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — drops `FunctionCallAddressable` and
//  `getView() -> AnyView`. Owns its own typed state: inbound-address +
//  approve-payload plumbing live directly on the sub-model. Cross-mutator
//  per the addendum — its chain-dependent THORChain-vs-EVM branching
//  reads the screen-owned coin via `@Binding`.
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

    /// THORChain inbound (router for ERC20, vault address otherwise).
    /// Set by `fetchInboundAddressAndSetupApproval()` once resolved.
    var toAddress: String = ""

    var isApprovalRequired: Bool = false
    var approvePayload: ERC20ApprovePayload?
    var customErrorMessage: String?

    /// Source coin — owned by this sub-model so the inbound-address /
    /// approve-payload logic can branch on chain + native-vs-token
    /// without dipping into screen-owned state.
    var coin: Coin

    /// Inbound-state error for non-RUNE source chains (halted/paused/missing
    /// inbound, or unavailable approval router). Tracked separately from the
    /// amount/address validation so the two never clobber each other; both
    /// are folded into `customErrorMessage` by `updateErrorMessage()`.
    @ObservationIgnored private var inboundStateError: String?

    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private var loadingTasks: [Task<Void, Never>] = []

    init(coin: Coin, vault: Vault) {
        self.coin = coin
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

    private var amountInRaw: BigInt {
        SendCryptoLogic.amountInRaw(coin: coin, amount: amount.formatToDecimal(digits: coin.decimals))
    }

    private func fetchInboundAddressAndSetupApproval() async {
        let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()

        if coin.chain == .thorChain {
            toAddress = coin.address
            isApprovalRequired = false
            approvePayload = nil
            inboundStateError = nil
            updateErrorMessage()
            return
        }

        let chainName = ThorchainService.getInboundChainName(for: coin.chain)
        guard let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
            inboundStateError = String(format: "inboundAddressNotFound".localized, chainName)
            updateErrorMessage()
            return
        }

        // A halted/paused source chain has no usable inbound vault; leave
        // `toAddress` empty so the form blocks submission instead of signing
        // with an empty destination (raw `Error_invalid_address` at sign time).
        if inbound.halted || inbound.global_trading_paused ?? false || inbound.chain_trading_paused ?? false || inbound.chain_lp_actions_paused ?? false {
            inboundStateError = String(format: "inboundPaused".localized, inbound.chain)
            updateErrorMessage()
            return
        }

        let destinationAddress: String
        if coin.shouldApprove {
            guard let router = inbound.router, !router.isEmpty else {
                inboundStateError = String(format: "routerNotAvailable".localized, inbound.chain)
                isApprovalRequired = false
                updateErrorMessage()
                return
            }
            destinationAddress = router
        } else {
            destinationAddress = inbound.address
        }

        toAddress = destinationAddress
        isApprovalRequired = coin.shouldApprove
        inboundStateError = nil
        if isApprovalRequired {
            approvePayload = toAddress.isEmpty ? nil : ERC20ApprovePayload(
                amount: amountInRaw,
                spender: toAddress
            )
        }
        updateErrorMessage()
    }

    func isAmountValid(against coin: Coin) -> Bool {
        amount > 0 && amount <= coin.balanceDecimal
    }

    func validate(against coin: Coin) {
        updateErrorMessage(against: coin)
    }

    var isTheFormValid: Bool {
        let amountValid = isAmountValid(against: coin)
        let thorValid = !thorAddress.isEmpty
        // For non-RUNE sources the mint is an on-chain transfer to the
        // THORChain inbound vault; require a resolved, non-paused inbound.
        let inboundValid = coin.chain == .thorChain || (!toAddress.isEmpty && inboundStateError == nil)
        return amountValid && thorValid && inboundValid
    }

    private func updateErrorMessage(against coin: Coin? = nil) {
        var errors: [String] = []
        let targetCoin = coin ?? self.coin

        if let inboundStateError {
            errors.append(inboundStateError)
        }
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
        let b = coin.balanceDecimal.formatForDisplay()
        return "( Balance: \(b) \(coin.ticker.uppercased()) )"
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
        guard isApprovalRequired, !toAddress.isEmpty else { return nil }
        return ERC20ApprovePayload(amount: amountInRaw, spender: toAddress)
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt
    ) -> SendTransaction {
        return SendTransaction.empty(coin: coin, vault: vault).copy(
            toAddress: toAddress.isEmpty ? "" : toAddress,
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
                Text(String(format: "targetAsset".localized, "\(model.coin.chain.swapAsset)-\(model.coin.ticker)"))
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
