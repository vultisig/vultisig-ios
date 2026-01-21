//
//  FunctionCallSecuredAsset.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 19/09/25.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Main ViewModel

class FunctionCallSecuredAsset: FunctionCallAddressable, ObservableObject {
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil

    // No operation selection needed - this is only for MINT
    @Published var amount: Decimal = 0.0
    @Published var thorAddress: String = ""

    // Validation flags
    @Published var amountValid: Bool = false
    @Published var thorAddressValid: Bool = false

    // ERC20 approval (for minting from ERC20 tokens)
    @Published var isApprovalRequired: Bool = false
    @Published var approvePayload: ERC20ApprovePayload?

    private var cancellables = Set<AnyCancellable>()

    // Domain models - needed for FunctionCallInstance compatibility
    var tx: SendTransaction
    private var vault: Vault

    var addressFields: [String: String] {
        get {
            ["thorAddress": thorAddress]
        }
        set {
            if let v = newValue["thorAddress"] {
                thorAddress = v
            }
        }
    }

    required init(tx: SendTransaction, vault: Vault) {
        self.tx = tx
        self.vault = vault
    }

    func initialize() {
        prefillAddresses()
        fetchInboundAddressAndSetupApproval()
        setupValidation()
        updateErrorMessage()
    }

    private func prefillAddresses() {
        // Automatically get THORChain address from vault - user doesn't need to fill this
        if let thorCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
            thorAddress = thorCoin.address
            thorAddressValid = true
        } else {
            thorAddressValid = false
            isTheFormValid = false
        }

        // No additional prefilling needed for mint/swap
    }

    // MARK: - Inbound address + approval (same logic as FunctionCallAddThorLP)

    private func fetchInboundAddressAndSetupApproval() {
        Task {
            let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()

            await MainActor.run {
                if self.tx.coin.chain == .thorChain {
                    // For THORChain, we don't need an inbound address initially
                    self.tx.toAddress = self.tx.coin.address
                    self.isApprovalRequired = false
                    self.approvePayload = nil
                    return
                } else {
                    // Normal send path: need inbound address for L1/EVM chains.
                    let chainName = ThorchainService.getInboundChainName(for: self.tx.coin.chain)
                    guard let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
                        return
                    }

                    if inbound.halted || inbound.global_trading_paused || inbound.chain_trading_paused || inbound.chain_lp_actions_paused {
                        self.customErrorMessage = String(format: NSLocalizedString("inboundPaused", comment: ""), inbound.chain)
                        self.isTheFormValid = false
                        return
                    }

                    let destinationAddress: String
                    if self.tx.coin.shouldApprove {
                        // ERC20 token → approval to router (router is required)
                        guard let router = inbound.router, !router.isEmpty else {
                            self.customErrorMessage = String(format: NSLocalizedString("routerNotAvailable", comment: ""), inbound.chain)
                            self.isApprovalRequired = false
                            self.isTheFormValid = false
                            return
                        }
                        destinationAddress = router
                    } else {
                        // Native token → direct to inbound address
                        destinationAddress = inbound.address
                    }

                    self.tx.toAddress = destinationAddress

                    // ERC20 approval only for ERC20 tokens
                    self.isApprovalRequired = self.tx.coin.shouldApprove
                    if self.isApprovalRequired {
                        self.approvePayload = self.tx.toAddress.isEmpty ? nil : ERC20ApprovePayload(
                            amount: self.tx.amountInRaw,
                            spender: self.tx.toAddress
                        )
                    }
                }
            }
        }
    }

    private func setupValidation() {
        // Amount validation
        $amount
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.validateAmount()
                self?.updateErrorMessage()
            }
            .store(in: &cancellables)

        // No destination address validation needed for mint/swap

        // Form validity for MINT operation
        Publishers.CombineLatest($amountValid, $thorAddressValid)
            .map { [weak self] amountValid, thorAddressValid in
                guard let self = self else { return false }

                // For mint, need valid amount AND valid THORChain address AND non-zero amount
                let isValid = amountValid && thorAddressValid && !self.amount.isZero

                // Update error messages
                self.updateErrorMessage()

                return isValid
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }

    private func validateAmount() {
        let currentBalance = tx.coin.balanceDecimal
        let isValidAmount = amount > 0 && amount <= currentBalance
        amountValid = isValidAmount
    }

    private func updateErrorMessage() {
        var errors: [String] = []

        // Check THORChain address
        if !thorAddressValid {
            let error = FunctionCallSecuredAssetError.thorAddressNotFound
            errors.append(error.localizedDescription)
        }

        // Check amount
        if amount <= 0 {
            let error = FunctionCallSecuredAssetError.invalidAmount
            errors.append(error.localizedDescription)
        } else if tx.coin.balanceDecimal < amount {
            let error = FunctionCallSecuredAssetError.insufficientBalance
            errors.append(error.localizedDescription)
        }

        // Concatenate all errors with newlines
        if errors.isEmpty {
            customErrorMessage = nil
        } else {
            customErrorMessage = errors.joined(separator: "\n")
        }
    }

    enum FunctionCallSecuredAssetError: LocalizedError {
        case invalidAmount
        case insufficientBalance
        case thorAddressNotFound

        var errorDescription: String? {
            switch self {
            case .invalidAmount:
                return NSLocalizedString("enterValidAmount", comment: "")
            case .insufficientBalance:
                return NSLocalizedString("insufficientBalanceForFunctions", comment: "Error message when user tries to enter amount greater than available balance")
            case .thorAddressNotFound:
                return NSLocalizedString("thorAddressNotFound", comment: "")
            }
        }
    }

    var description: String {
        return toString()
    }

    func toString() -> String {
        return "SECURE+:\(thorAddress)"
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
        guard isApprovalRequired, !tx.toAddress.isEmpty else {
            return nil
        }
        return ERC20ApprovePayload(amount: tx.amountInRaw, spender: tx.toAddress)
    }

    func getView() -> AnyView {
        AnyView(FunctionCallSecuredAssetView(model: self))
    }
}

// MARK: - View
struct FunctionCallSecuredAssetView: View {
    @ObservedObject var model: FunctionCallSecuredAsset

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("mintSecuredAsset", comment: ""))
                    .font(.headline)
                Text(String(format: NSLocalizedString("targetAsset", comment: ""), "\(model.tx.coin.chain.swapAsset)-\(model.tx.coin.ticker)"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Show ERC20 approval info if needed
            if model.isApprovalRequired {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("erc20ApprovalRequired", comment: ""))
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(NSLocalizedString("erc20ApprovalRequiredMessage", comment: ""))
                        .font(.body)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("approvalTransaction", comment: ""))
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(NSLocalizedString("mintTransaction", comment: ""))
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.leading, 16)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                StyledFloatingPointField(
                    label: NSLocalizedString("amount", comment: ""),
                    placeholder: NSLocalizedString("enterAmount", comment: ""),
                    value: Binding(
                        get: { model.amount },
                        set: { model.amount = $0 }
                    ),
                    isValid: Binding(
                        get: { model.amountValid },
                        set: { model.amountValid = $0 }
                    )
                )

                Text(model.balance)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let errorMessage = model.customErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Show THORChain address info (read-only)
            if !model.thorAddress.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("thorAddressAutoFilled", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(model.thorAddress)
                        .font(.footnote)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            // No additional fields needed for mint/swap operations

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("generatedMemo", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
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
}
