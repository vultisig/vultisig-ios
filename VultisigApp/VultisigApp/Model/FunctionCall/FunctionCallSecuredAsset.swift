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
    private var functionCallViewModel: FunctionCallViewModel
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
    
    required init(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault) {
        self.tx = tx
        self.functionCallViewModel = functionCallViewModel
        self.vault = vault
    }
    
    func initialize() {
        prefillAddresses()
        fetchInboundAddressAndSetupApproval()
        setupValidation()
    }
    
    private func prefillAddresses() {
        // Automatically get THORChain address from vault - user doesn't need to fill this
        if let thorCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
            thorAddress = thorCoin.address
            thorAddressValid = true
            print("DEBUG: THORChain address prefilled: \(thorAddress)")
        } else {
            print("DEBUG: No THORChain coin found in vault")
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
                        return
                    }
                    
                    let destinationAddress: String
                    if self.tx.coin.shouldApprove {
                        // ERC20 token → approval to router
                        destinationAddress = inbound.router ?? inbound.address
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
            .sink { [weak self] amount in
                self?.validateAmount()
            }
            .store(in: &cancellables)
        
        // No destination address validation needed for mint/swap
        
        // Form validity for MINT operation
        Publishers.CombineLatest($amountValid, $thorAddressValid)
            .map { [weak self] amountValid, thorAddressValid in
                guard let self = self else { return false }
                
                // For mint, need valid amount AND valid THORChain address AND non-zero amount
                let isValid = amountValid && thorAddressValid && !self.amount.isZero
                
                // Set specific error message if THORChain address is missing
                if !thorAddressValid && self.customErrorMessage == nil {
                    self.customErrorMessage = "THORChain address not found in vault. Please ensure you have RUNE in your vault."
                }
                
                print("DEBUG: Form validation - MINT, amountValid: \(amountValid), thorAddressValid: \(thorAddressValid), amount: \(self.amount), isValid: \(isValid)")
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
        
        print("DEBUG: Amount validation - amount: \(amount), currentBalance: \(currentBalance), amountValid: \(amountValid)")
        
        if amount <= 0 {
            amountValid = false
            customErrorMessage = "Please enter a valid amount greater than zero."
        } else if currentBalance < amount {
            amountValid = false
            customErrorMessage = NSLocalizedString("insufficientBalanceForFunctions", comment: "Error message when user tries to enter amount greater than available balance")
        } else {
            customErrorMessage = nil
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
    
    func buildApprovePayload() async throws -> ERC20ApprovePayload? {
        guard isApprovalRequired, !tx.toAddress.isEmpty else {
            return nil
        }
        return ERC20ApprovePayload(amount: tx.amountInRaw, spender: tx.toAddress)
    }
    
    func getView() -> AnyView {
        AnyView(VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mint Secured Asset (SECURE+)")
                    .font(.headline)
                Text("Target Asset: \(tx.coin.chain.swapAsset)-\(tx.coin.ticker)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Show ERC20 approval info if needed
            if isApprovalRequired {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ERC20 Approval Required")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("This ERC20 token requires approval before minting. Two transactions will be signed:")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Approval transaction")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("2. Mint secured asset transaction")
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
                        get: { self.amount },
                        set: { self.amount = $0 }
                    ),
                    isValid: Binding(
                        get: { self.amountValid },
                        set: { self.amountValid = $0 }
                    )
                )
                
                Text(balance)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let errorMessage = customErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Show THORChain address info (read-only)
            if !thorAddress.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THORChain Address (auto-filled)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(thorAddress)
                        .font(.footnote)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            // No additional fields needed for mint/swap operations
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Generated Memo:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(toString())
                    .font(.footnote)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            
        }.onAppear {
            self.initialize()
        })
    }
}