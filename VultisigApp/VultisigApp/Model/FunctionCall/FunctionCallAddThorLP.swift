//
//  FunctionCallAddThorLP.swift
//  VultisigApp
//

import SwiftUI
import Foundation
import Combine

// MARK: - Main ViewModel

class FunctionCallAddThorLP: FunctionCallAddressable, ObservableObject {
    // MARK: Published inputs / UI state
    @Published var amount: Decimal = 0.0
    @Published var pairedAddress: String = ""
    @Published var selectedPool: IdentifiableString = .init(value: "")
    
    // Validation flags
    @Published var amountValid: Bool = false
    @Published var pairedAddressValid: Bool = true
    @Published var poolValid: Bool = false
    @Published var isTheFormValid: Bool = false
    
    // Pools
    @Published var availablePools: [IdentifiableString] = []
    @Published var isLoadingPools: Bool = true
    @Published var loadError: String? = nil
    
    // Mapping display name -> full pool asset string
    private var poolNameMap: [String: String] = [:]
    @Published var pairedAssetBalance: String = ""
    @Published var selectedPoolBalance: String = ""
    
    // ERC20 approval
    @Published var isApprovalRequired: Bool = false
    @Published var approvePayload: ERC20ApprovePayload?
    
    // Internals
    private var cancellables = Set<AnyCancellable>()
    
    // Domain models
    var tx: SendTransaction
    private var functionCallViewModel: FunctionCallViewModel
    private var vault: Vault
    
    // MARK: Addressable conformance helpers
    var addressFields: [String: String] {
        get { ["pairedAddress": pairedAddress] }
        set {
            if let v = newValue["pairedAddress"] {
                pairedAddress = v
            }
        }
    }
    
    // MARK: Init
    required init(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault) {
        self.tx = tx
        self.functionCallViewModel = functionCallViewModel
        self.vault = vault
        
        prefillPairedAddress()
        setupValidation()
        loadInitialState()
    }
    
    private func loadInitialState() {
        fetchInboundAddressAndSetupApproval()
        Task { @MainActor in
            await loadPools()
        }
    }
    
    // MARK: - Inbound address + approval
    
    private func fetchInboundAddressAndSetupApproval() {
        Task { @MainActor in
            let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
            
            if tx.coin.chain == .thorChain {
                // For THORChain, we don't need an inbound address initially (it's set when pool is selected)
                // The toAddress will be set when pool is selected

                isApprovalRequired = false
                approvePayload = nil
                return
            } else {
                // Normal send path: need inbound address for L1/EVM chains.
                let chainName = ThorchainService.getInboundChainName(for: tx.coin.chain)
                guard let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
                    return
                }
                
                if inbound.halted || inbound.global_trading_paused || inbound.chain_trading_paused || inbound.chain_lp_actions_paused {
                    return
                }
                
                let destinationAddress: String
                if tx.coin.shouldApprove {
                    // ERC20 token (e.g., USDC) → approval to router
                    destinationAddress = inbound.router ?? inbound.address

                } else {
                    // Native token (e.g., ETH) → direct to inbound address
                    destinationAddress = inbound.address

                }
                
                tx.toAddress = destinationAddress
                
                // ERC20 approval only for non-RUNE ERC20 tokens
                isApprovalRequired = tx.coin.shouldApprove
                if isApprovalRequired {
                    if !tx.toAddress.isEmpty {
                        let payload = ERC20ApprovePayload(amount: tx.amountInRaw, spender: tx.toAddress)
                        self.approvePayload = payload

                    } else {
                        // Address not yet set, wait for pool selection
                        self.approvePayload = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Pool loading
    
    @MainActor
    func loadPools() async {
        isLoadingPools = true
        loadError = nil
        
        do {
            // The retry logic is now handled within ThorchainService.fetchLPPools()
            let allPools = try await ThorchainService.shared.fetchLPPools()
            
            var poolOptions: [IdentifiableString] = []
            var nameMap: [String: String] = [:]
            
            if tx.coin.chain == .thorChain {
                for pool in allPools {
                    let assetName = pool.asset
                    let cleanName = ThorchainService.cleanPoolName(assetName)
                    poolOptions.append(IdentifiableString(value: cleanName))
                    nameMap[cleanName] = assetName
                }
            } else {
                let currentSwap = tx.coin.chain.swapAsset.uppercased()
                let filtered = allPools.filter { pool in
                    let components = pool.asset
                        .split(separator: ".")
                        .map { String($0).uppercased() }
                    return components.count >= 2 && components[0] == currentSwap
                }
                for pool in filtered {
                    let assetName = pool.asset
                    let cleanName = ThorchainService.cleanPoolName(assetName)
                    poolOptions.append(IdentifiableString(value: cleanName))
                    nameMap[cleanName] = assetName
                }
            }
            
            // Commit
            self.poolNameMap = nameMap
            self.availablePools = poolOptions
            self.isLoadingPools = false
            self.loadError = nil
            
            // Pool options loaded successfully
            
            if tx.coin.chain != .thorChain && poolOptions.count == 1 {
                // auto-select single pool for L1
                self.selectedPool = poolOptions[0]
                self.poolValid = true
            }
        } catch {
            self.availablePools = []
            self.isLoadingPools = false
            self.loadError = "Failed to load pools. Please check your connection and try again."
        }
    }
    
    // MARK: - Prefill logic
    
    private func prefillPairedAddress() {
        if tx.coin.chain == .thorChain {
            pairedAddress = ""
            pairedAddressValid = false
        } else if let thorCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
            pairedAddress = thorCoin.address
            pairedAddressValid = true
        } else {
            pairedAddress = ""
            pairedAddressValid = false
        }
    }
    
    func prefillPairedAddressForPool(_ poolName: String) {
        let components = poolName.split(separator: ".").map { String($0).uppercased() }
        guard components.count >= 2 else {
            pairedAddress = ""
            pairedAddressValid = false
            pairedAssetBalance = ""
            return
        }
        
        let chainPrefix = components[0]
        let assetTicker = components[1]
        
        guard let chainCoin = vault.coins.first(where: {
            $0.isNativeToken && $0.chain.swapAsset.uppercased() == chainPrefix
        }) else {
            pairedAddress = ""
            pairedAddressValid = false
            pairedAssetBalance = ""
            return
        }
        
        pairedAddress = chainCoin.address
        pairedAddressValid = true
        
        if tx.coin.chain == .thorChain {
            Task { @MainActor in
                let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
                let chainName = ThorchainService.getInboundChainName(for: chainCoin.chain)
                if let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }),
                   !(inbound.halted || inbound.global_trading_paused || inbound.chain_trading_paused || inbound.chain_lp_actions_paused) {
                    tx.toAddress = inbound.address
                } else {
                    // Inbound address not available or chain is halted
                    print("Warning: Inbound address not available for chain \(chainName)")
                }
            }
        }
        
        if let assetCoin = vault.coins.first(where: { $0.chain == chainCoin.chain && $0.ticker.uppercased() == assetTicker }) {
            let balance = assetCoin.balanceDecimal.formatForDisplay()
            pairedAssetBalance = "( Balance: \(balance) \(assetCoin.ticker.uppercased()) )"
        } else if assetTicker == chainPrefix {
            let balance = chainCoin.balanceDecimal.formatForDisplay()
            pairedAssetBalance = "( Balance: \(balance) \(chainCoin.ticker.uppercased()) )"
        } else {
            pairedAssetBalance = "( \(assetTicker) not found in vault )"
        }
    }
    
    func updateSelectedPoolBalance(_ poolName: String) {
        // If on THORChain, balance is always RUNE
        if tx.coin.chain == .thorChain {
            selectedPoolBalance = balance  // This is RUNE balance
            return
        }
        
        // For external chains, show balance of the asset being added to the pool
        let components = poolName.split(separator: ".").map { String($0).uppercased() }
        guard components.count >= 2 else {
            selectedPoolBalance = balance  // fallback to tx.coin balance
            return
        }
        
        let chainPrefix = components[0]
        let assetTicker = components[1]
        
        // Find the chain's coins
        let chainCoins = vault.coins.filter { $0.chain.swapAsset.uppercased() == chainPrefix }
        
        // Check if it's the native token (e.g., BASE.ETH -> ETH on Base chain)
        if assetTicker == chainPrefix || assetTicker == "ETH" {
            if let nativeCoin = chainCoins.first(where: { $0.isNativeToken }) {
                let b = nativeCoin.balanceDecimal.formatForDisplay()
                selectedPoolBalance = "( Balance: \(b) \(nativeCoin.ticker.uppercased()) )"
                return
            }
        }
        
        // Check for specific token (e.g., BASE.USDC -> USDC on Base chain)
        if let tokenCoin = chainCoins.first(where: { $0.ticker.uppercased() == assetTicker }) {
            let b = tokenCoin.balanceDecimal.formatForDisplay()
            selectedPoolBalance = "( Balance: \(b) \(tokenCoin.ticker.uppercased()) )"
            return
        }
        
        // Asset not found in vault
        selectedPoolBalance = "( \(assetTicker) not found in vault )"
    }
    
    // MARK: - Validation
    
    private func setupValidation() {
        Publishers.CombineLatest3($amountValid, $pairedAddressValid, $poolValid)
            .map { $0 && $1 && $2 }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Memo / Dictionary
    
    private var fullPoolName: String {
        poolNameMap[selectedPool.value] ?? selectedPool.value
    }
    
    var description: String {
        toString()
    }
    
    func toString() -> String {
        let address = pairedAddress.nilIfEmpty
        let lpData = AddLPMemoData(pool: fullPoolName, pairedAddress: address)
        return lpData.memo
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("pool", fullPoolName)
        dict.set("pairedAddress", pairedAddress)
        dict.set("memo", toString())
        return dict
    }
    
    func buildApprovePayload() async throws -> ERC20ApprovePayload? {
        guard isApprovalRequired, !tx.toAddress.isEmpty else {
            return nil
        }
        return ERC20ApprovePayload(amount: tx.amountInRaw, spender: tx.toAddress)
    }
    
    var balance: String {
        let b = tx.coin.balanceDecimal.formatForDisplay()
        return "( Balance: \(b) \(tx.coin.ticker.uppercased()) )"
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallAddThorLPView(model: self))
    }
    
    // MARK: - Chain name mapping moved to THORChainUtils
}

// MARK: - Views

struct FunctionCallAddThorLPView: View {
    @ObservedObject var model: FunctionCallAddThorLP
    
    var body: some View {
        VStack {
            PoolSelectorSection(model: model)
            
            if model.isApprovalRequired {
                ApprovalInfoSection()
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.blue600.opacity(0.1))
                    .cornerRadius(10)
            }
            
            StyledFloatingPointField(
                label: {
                    // If adding RUNE (thorChain), show RUNE balance. Otherwise show the selected pool's asset balance.
                    if model.tx.coin.chain == .thorChain {
                        return "Amount \(model.balance)"
                    } else if !model.selectedPoolBalance.isEmpty {
                        return "Amount \(model.selectedPoolBalance)"
                    } else {
                        return "Amount \(model.balance)"
                    }
                }(),
                placeholder: "Enter amount",
                value: Binding(get: { model.amount }, set: { model.amount = $0 }),
                isValid: Binding(get: { model.amountValid }, set: { model.amountValid = $0 })
            )
        }
    }
}

struct PoolSelectorSection: View {
    @ObservedObject var model: FunctionCallAddThorLP
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            if model.isLoadingPools {
                loadingView
            } else if !model.isLoadingPools && model.availablePools.isEmpty {
                errorView
            } else {
                dropdownView
            }
        }
    }
    
    private var loadingView: some View {
        HStack(spacing: 12) {
            Text("Loading pools...")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
            
            Spacer()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.7)
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
    }
    
    private var errorView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.body16Menlo)
                    .foregroundColor(.orange)
                
                Text(model.loadError ?? "No pools available")
                    .font(.body14Menlo)
                    .foregroundColor(.neutral0)
                    .lineLimit(2)
                
                Spacer()
                
                Button {
                    model.loadError = nil
                    model.isLoadingPools = true
                    Task {
                        await model.loadPools()
                    }
                } label: {
                    Text("Retry")
                        .font(.caption)
                        .foregroundColor(.turquoise600)
                }
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue600)
            .cornerRadius(10)
        }
    }
    
    private var dropdownView: some View {
        GenericSelectorDropDown(
            items: Binding(get: { model.availablePools }, set: { _ in }),
            selected: Binding(get: { model.selectedPool }, set: { model.selectedPool = $0 }),
            mandatoryMessage: "*",
            descriptionProvider: { $0.value.isEmpty ? "Select pool" : $0.value },
            onSelect: { pool in
                model.selectedPool = pool
                model.poolValid = !pool.value.isEmpty
                if !pool.value.isEmpty {
                    if model.tx.coin.chain == .thorChain {
                        model.prefillPairedAddressForPool(pool.value)
                    } else {
                        // Only update balance for external chains
                        model.updateSelectedPoolBalance(pool.value)
                    }
                }
            }
        )
        .onAppear {
        }
    }
}

struct ApprovalInfoSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ERC20 Approval Required")
                .font(.body16MenloBold)
                .foregroundColor(.neutral0)
            
            Text("This ERC20 token requires approval before adding to liquidity pool. Two transactions will be signed:")
                .font(.body14Menlo)
                .foregroundColor(.neutral0)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Approval transaction")
                    .font(.body12Menlo)
                    .foregroundColor(.turquoise600)
                Text("2. Add liquidity transaction")
                    .font(.body12Menlo)
                    .foregroundColor(.turquoise600)
            }
            .padding(.leading, 16)
        }
    }
}
