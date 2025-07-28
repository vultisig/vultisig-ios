//
//  FunctionCallAddThorLP.swift
//  VultisigApp
//

import SwiftUI
import Foundation
import Combine

class FunctionCallAddThorLP: FunctionCallAddressable, ObservableObject {
    @Published var amount: Decimal = 0.0
    @Published var pairedAddress: String = ""
    @Published var selectedPool: IdentifiableString = .init(value: "")
    
    // Internal validation
    @Published var amountValid: Bool = false
    @Published var pairedAddressValid: Bool = true
    @Published var poolValid: Bool = false
    @Published var isTheFormValid: Bool = false
    
    // Available pools
    @Published var availablePools: [IdentifiableString] = []
    @Published var isLoadingPools: Bool = true  // Start as loading
    @Published var loadError: String? = nil
    
    // Map of display names to full pool names
    private var poolNameMap: [String: String] = [:]
    var retryCount = 0
    private let maxRetries = 3
    
    // Balance display for paired asset
    @Published var pairedAssetBalance: String = ""
    
    var tx: SendTransaction
    private var functionCallViewModel: FunctionCallViewModel
    private var vault: Vault
    
    var addressFields: [String: String] {
        get {
            if tx.coin.chain == .thorChain {
                // For THORChain, pairedAddress is used in the memo
                let fields = ["pairedAddress": pairedAddress]
                return fields
            } else {
                // For L1 assets, pairedAddress is used in the memo (THORChain address)
                // toAddress is automatically set by fetchInboundAddress()
                let fields = ["pairedAddress": pairedAddress]
                return fields
            }
        }
        set {
            if let value = newValue["pairedAddress"] {
                pairedAddress = value
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    required init(tx: SendTransaction, functionCallViewModel: FunctionCallViewModel, vault: Vault) {
        self.tx = tx
        self.functionCallViewModel = functionCallViewModel
        self.vault = vault
        
        // Prefill paired address based on the asset type
        prefillPairedAddress()
        
        setupValidation()
        
        // Fetch the inbound address (pool address) for the transaction
        fetchInboundAddress()
        
        // Only load pools for RUNE
        if tx.coin.chain == .thorChain {
            // Ensure isLoadingPools is true before starting
            self.isLoadingPools = true
            
            // Load pools after a small delay to ensure UI is ready
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                loadPools()
            }
        } else {
            // For L1 assets, set the pool to the native asset pool
            // e.g., for BTC it would be "BTC.BTC", for ETH it would be "ETH.ETH"
            let swapAsset = tx.coin.chain.swapAsset
            let poolName = "\(swapAsset).\(swapAsset)"
            self.selectedPool = IdentifiableString(value: poolName)
            self.poolValid = true
            self.isLoadingPools = false
            // Store the full pool name in the map
            self.poolNameMap[poolName] = poolName
        }
    }
    
    private func fetchInboundAddress() {
        Task { @MainActor in
            let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
            
            if tx.coin.chain == .thorChain {
                // For THORChain, we don't need an inbound address (it's a deposit)
                // The toAddress will be set when pool is selected
                return
            } else {
                // For L1 assets, find the inbound address for this chain
                let chainName = getInboundChainName(for: tx.coin.chain)
                
                if let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) {
                    // Check if chain is halted or paused
                    if inbound.halted || inbound.global_trading_paused || inbound.chain_trading_paused || inbound.chain_lp_actions_paused {
                        print("FunctionCallAddThorLP: Chain \(chainName) is halted or paused for LP operations")
                        return
                    }
                    
                    // Set the inbound address as the destination for the transaction
                    tx.toAddress = inbound.address
                    print("FunctionCallAddThorLP: Set toAddress to \(inbound.address) for chain \(chainName)")
                } else {
                    print("FunctionCallAddThorLP: No inbound address found for chain \(chainName)")
                }
            }
        }
    }
    
    private func getInboundChainName(for chain: Chain) -> String {
        // Map internal chain names to THORChain inbound address chain names
        switch chain {
        case .bitcoin:
            return "BTC"
        case .ethereum:
            return "ETH"
        case .avalanche:
            return "AVAX"
        case .bscChain:
            return "BSC"
        case .arbitrum:
            return "ARB"
        case .base:
            return "BASE"
        case .optimism:
            return "OP"
        case .polygon:
            return "MATIC"
        case .litecoin:
            return "LTC"
        case .bitcoinCash:
            return "BCH"
        case .dogecoin:
            return "DOGE"
        case .gaiaChain:
            return "GAIA"
        case .thorChain:
            return "THOR"
        default:
            // For unknown chains, use the chain's swapAsset
            return chain.swapAsset.uppercased()
        }
    }
    
    var balance: String {
        let balance = tx.coin.balanceDecimal.formatForDisplay()
        return "( Balance: \(balance) \(tx.coin.ticker.uppercased()) )"
    }
    
    private func prefillPairedAddress() {
        if tx.coin.chain == .thorChain {
            // For RUNE, paired address will be set when user selects a pool
            pairedAddress = ""
            pairedAddressValid = false // Will be set to true when pool is selected
        } else {
            // For L1 assets, automatically get user's THORChain address
            if let thorCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
                pairedAddress = thorCoin.address
                pairedAddressValid = true
            } else {
                pairedAddress = ""
                pairedAddressValid = false
            }
        }
    }
    
    func prefillPairedAddressForPool(_ poolName: String) {
        // Split pool name to get chain and asset (e.g., "ETH.USDC" -> ["ETH", "USDC"])
        let poolComponents = poolName.split(separator: ".").map { String($0).uppercased() }
        guard poolComponents.count >= 2 else {
            pairedAddress = ""
            pairedAddressValid = false
            self.pairedAssetBalance = ""
            return
        }
        
        let chainPrefix = poolComponents[0]
        let assetTicker = poolComponents[1]
        
        // Find the chain by matching swap asset
        if let chainCoin = vault.coins.first(where: { coin in
            coin.isNativeToken && coin.chain.swapAsset.uppercased() == chainPrefix
        }) {
            pairedAddress = chainCoin.address
            pairedAddressValid = true
            
            // For THORChain adding to a pool, set the inbound address as destination
            if tx.coin.chain == .thorChain {
                Task { @MainActor in
                    let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
                    let chainName = getInboundChainName(for: chainCoin.chain)
                    
                    if let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) {
                        // Check if chain is halted or paused
                        if inbound.halted || inbound.global_trading_paused || inbound.chain_trading_paused || inbound.chain_lp_actions_paused {
                            print("FunctionCallAddThorLP: Chain \(chainName) is halted or paused for LP operations")
                            return
                        }
                        
                        // Set the inbound address as the destination for RUNE transaction
                        tx.toAddress = inbound.address
                        print("FunctionCallAddThorLP: Set toAddress to \(inbound.address) for RUNE->pool \(poolName)")
                    }
                }
            }
            
            // Now find the specific asset on that chain to show its balance
            if let assetCoin = vault.coins.first(where: { coin in
                coin.chain == chainCoin.chain && coin.ticker.uppercased() == assetTicker
            }) {
                // Show the balance of the specific asset in the pool
                let balance = assetCoin.balanceDecimal.formatForDisplay()
                self.pairedAssetBalance = "( Balance: \(balance) \(assetCoin.ticker.uppercased()) )"
            } else if assetTicker == chainPrefix {
                // For native token pools (e.g., "BTC.BTC"), use the chain coin
                let balance = chainCoin.balanceDecimal.formatForDisplay()
                self.pairedAssetBalance = "( Balance: \(balance) \(chainCoin.ticker.uppercased()) )"
            } else {
                // Asset not found in vault
                self.pairedAssetBalance = "( \(assetTicker) not found in vault )"
            }
        } else {
            // Chain not found
            pairedAddress = ""
            pairedAddressValid = false
            self.pairedAssetBalance = ""
        }
    }
    
    private func setupValidation() {
        Publishers.CombineLatest3($amountValid, $pairedAddressValid, $poolValid)
            .map { amountValid, pairedAddressValid, poolValid in
                // For validation, we need:
                // - Valid amount
                // - Valid pool (always true for L1 assets, selected for RUNE)
                // - Valid paired address (automatically set)
                return amountValid && poolValid && pairedAddressValid
            }
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    private func cleanPoolName(_ asset: String) -> String {
        // Remove contract addresses from pool names
        // Examples: 
        // "AVAX.SOL-0XFE6B19286885A4F7F55ADAD09C3CD1F906D2478F" -> "AVAX.SOL"
        // "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48" -> "ETH.USDC"
        
        if let dashIndex = asset.firstIndex(of: "-"),
           let hexPrefix = asset[asset.index(after: dashIndex)...].firstIndex(of: "0"),
           asset[hexPrefix...].starts(with: "0X") {
            // Remove everything from the dash onwards
            return String(asset[..<dashIndex])
        }
        
        // Return as-is if no contract address found
        return asset
    }
    
    func loadPools() {
        Task { @MainActor in
            print("FunctionCallAddThorLP: loadPools() called, isLoadingPools = \(self.isLoadingPools)")
            
            // Set a timeout for the entire operation
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 15_000_000_000) // 15 second timeout
                if self.isLoadingPools {
                    print("FunctionCallAddThorLP: Pool loading timeout!")
                    await MainActor.run {
                        self.availablePools = []
                        self.isLoadingPools = false
                    }
                }
            }
            
            do {
                if tx.coin.chain == .thorChain {
                    // For RUNE, fetch all available pools
                    print("FunctionCallAddThorLP: Loading pools for RUNE...")
                    
                    let startTime = Date()
                    let pools = try await Task.detached {
                        try await ThorchainService.shared.fetchLPPools()
                    }.value
                    let loadTime = Date().timeIntervalSince(startTime)
                    
                    // Cancel timeout task if we finished successfully
                    timeoutTask.cancel()
                    
                    print("FunctionCallAddThorLP: Fetched \(pools.count) pools in \(String(format: "%.2f", loadTime))s")
                    
                    // Build pool options without "Select pool" prefix
                    var poolOptions: [IdentifiableString] = []
                    var nameMap: [String: String] = [:]
                    
                    for pool in pools {
                        // Clean up pool name by removing contract addresses
                        let cleanName = cleanPoolName(pool.asset)
                        poolOptions.append(IdentifiableString(value: cleanName))
                        nameMap[cleanName] = pool.asset  // Map display name to full name
                    }
                    
                    // Force UI update on main thread
                    await MainActor.run {
                        self.objectWillChange.send()  // Force SwiftUI to update
                        self.poolNameMap = nameMap
                        self.availablePools = poolOptions
                        self.isLoadingPools = false
                        self.loadError = nil  // Clear any previous errors
                        self.retryCount = 0   // Reset retry count on success
                        print("FunctionCallAddThorLP: Updated availablePools with \(self.availablePools.count) options")
                        print("FunctionCallAddThorLP: availablePools.isEmpty = \(self.availablePools.isEmpty)")
                        print("FunctionCallAddThorLP: isLoadingPools = \(self.isLoadingPools)")
                        
                        // Debug: print first few pools
                        if pools.count > 0 {
                            print("FunctionCallAddThorLP: First few pools: \(pools.prefix(5).map { cleanPoolName($0.asset) })")
                        }
                    }
                } else {
                    // For L1 assets, use the chain's swap asset
                    let poolName = "\(tx.coin.chain.swapAsset).\(tx.coin.ticker.uppercased())"
                    
                    // Cancel timeout task
                    timeoutTask.cancel()
                    
                    await MainActor.run {
                        self.availablePools = [IdentifiableString(value: poolName)]
                        self.selectedPool = IdentifiableString(value: poolName)
                        self.poolValid = true
                        self.isLoadingPools = false
                    }
                }
            } catch {
                print("FunctionCallAddThorLP: Error loading pools: \(error)")
                print("FunctionCallAddThorLP: Error details: \(error.localizedDescription)")
                
                // Cancel timeout task
                timeoutTask.cancel()
                
                // Check if we should retry
                if retryCount < maxRetries {
                    retryCount += 1
                    print("FunctionCallAddThorLP: Retrying... (attempt \(retryCount + 1)/\(maxRetries + 1))")
                    
                    // Wait before retrying (exponential backoff)
                    let retryDelay = UInt64(pow(2.0, Double(retryCount - 1))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: retryDelay)
                    
                    // Retry
                    loadPools()
                } else {
                    // Keep empty on error to show retry button
                    await MainActor.run {
                        self.objectWillChange.send()  // Force SwiftUI to update
                        self.availablePools = []
                        self.isLoadingPools = false
                        self.loadError = "Failed to load pools. Please check your connection and try again."
                    }
                }
            }
        }
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        // Get the full pool name from the map (or use the display name if not found)
        let fullPoolName = poolNameMap[selectedPool.value] ?? selectedPool.value
        
        if tx.coin.chain == .thorChain {
            // For THORChain: include the paired asset's address (required)
            let address = pairedAddress.nilIfEmpty
            let lpData = AddLPMemoData(
                pool: fullPoolName,
                pairedAddress: address
            )
            return lpData.memo
        } else {
            // For L1 assets: just include the pool name in the memo
            // The destination address is already set in tx.toAddress via fetchInboundAddress()
            let lpData = AddLPMemoData(
                pool: fullPoolName,
                pairedAddress: nil
            )
            return lpData.memo
        }
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        // Store the full pool name in the dictionary
        let fullPoolName = poolNameMap[selectedPool.value] ?? selectedPool.value
        dict.set("pool", fullPoolName)
        
        if tx.coin.chain == .thorChain {
            // For THORChain, store pairedAddress in the memo dictionary
            dict.set("pairedAddress", pairedAddress)
        } else {
            // For L1 assets, store the THORChain address in pairedAddress
            dict.set("pairedAddress", pairedAddress)
        }
        
        dict.set("memo", toString())
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallAddThorLPView(model: self))
    }
}

struct FunctionCallAddThorLPView: View {
    @ObservedObject var model: FunctionCallAddThorLP
    
    var body: some View {
        VStack {
            
            // Pool selection for RUNE only
            if model.tx.coin.chain == .thorChain {
                VStack(alignment: .leading, spacing: 0) {
                    let _ = print("FunctionCallAddThorLP UI: Rendering pool selector - isLoadingPools=\(model.isLoadingPools), availablePools.count=\(model.availablePools.count)")
                    
                    if model.isLoadingPools {
                            // Show loading state as a disabled dropdown
                            HStack(spacing: 12) {
                                Text("Loading pools...")
                                    .font(.body16Menlo)
                                    .foregroundColor(.neutral0)
                                    .onAppear {
                                        print("FunctionCallAddThorLP UI: Showing loading state")
                                    }
                                
                                Spacer()
                                
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.7)
                            }
                            .frame(height: 48)
                            .padding(.horizontal, 12)
                            .background(Color.blue600)
                            .cornerRadius(10)
                                            } else if !model.isLoadingPools && model.availablePools.isEmpty {
                        // Show error state
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.body16Menlo)
                                    .foregroundColor(.orange)
                                
                                Text(model.loadError ?? "No pools available")
                                    .font(.body14Menlo)
                                    .foregroundColor(.neutral0)
                                    .lineLimit(2)
                                    .onAppear {
                                        print("FunctionCallAddThorLP UI: Showing error - availablePools.count = \(model.availablePools.count)")
                                    }
                                
                                Spacer()
                                
                                Button {
                                    model.retryCount = 0  // Reset retry count
                                    model.loadError = nil
                                    model.isLoadingPools = true
                                    model.loadPools()
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
                        } else {
                            GenericSelectorDropDown(
                                items: Binding(
                                    get: { model.availablePools },
                                    set: { _ in }
                                ),
                                selected: Binding(
                                    get: { model.selectedPool },
                                    set: { model.selectedPool = $0 }
                                ),
                                mandatoryMessage: "*",
                                descriptionProvider: { $0.value.isEmpty ? "Select pool" : $0.value },
                                onSelect: { pool in
                                    model.selectedPool = pool
                                    model.poolValid = !pool.value.isEmpty
                                    
                                    // When RUNE selects a pool, prefill the paired address
                                    if model.tx.coin.chain == .thorChain && !pool.value.isEmpty {
                                        model.prefillPairedAddressForPool(pool.value)
                                    }
                                }
                            )
                            .onAppear {
                                print("FunctionCallAddThorLP UI: Showing dropdown - availablePools.count = \(model.availablePools.count)")
                                print("FunctionCallAddThorLP UI: selectedPool = \(model.selectedPool.value)")
                                print("FunctionCallAddThorLP UI: isLoadingPools = \(model.isLoadingPools)")
                            }
                    }
                }
            }
            
            // Amount field - shows balance of the asset being added
            StyledFloatingPointField(
                placeholder: Binding(
                    get: { 
                        if model.tx.coin.chain == .thorChain && !model.pairedAssetBalance.isEmpty {
                            // For RUNE, show the selected pool asset's balance
                            return "Amount \(model.pairedAssetBalance)"
                        } else {
                            // For L1 assets, show their own balance
                            return "Amount \(model.balance)"
                        }
                    },
                    set: { _ in }
                ),
                value: Binding(
                    get: { model.amount },
                    set: { model.amount = $0 }
                ),
                isValid: Binding(
                    get: { model.amountValid },
                    set: { model.amountValid = $0 }
                )
            )
        }
    }
} 