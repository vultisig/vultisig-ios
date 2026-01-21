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
    @Published var customErrorMessage: String? = nil
    
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
    required init(tx: SendTransaction, vault: Vault) {
        self.tx = tx
        self.vault = vault
    }
    
    func initialize() {
        prefillPairedAddress()
        setupValidation()
        loadInitialState()
    }
    
    private func loadInitialState() {
        fetchInboundAddressAndSetupApproval()
        loadPools()
    }
    
    // MARK: - Inbound address + approval
    
    private func fetchInboundAddressAndSetupApproval() {
        Task {
            let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
            
            await MainActor.run {
                if self.tx.coin.chain == .thorChain {
                    // For THORChain, we don't need an inbound address initially (it's set when pool is selected)
                    // The toAddress will be set when pool is selected
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
                        // ERC20 token (e.g., USDC) → approval to router
                        destinationAddress = inbound.router ?? inbound.address
                    } else {
                        // Native token (e.g., ETH) → direct to inbound address
                        destinationAddress = inbound.address
                    }
                    
                    self.tx.toAddress = destinationAddress
                    
                    // ERC20 approval only for non-RUNE ERC20 tokens
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
    
    // MARK: - Pool loading
    
    func loadPools() {
        isLoadingPools = true
        loadError = nil
        
        Task {
            do {
                let allPools = try await ThorchainService.shared.fetchLPPools()
                
                var poolOptions: [IdentifiableString] = []
                var nameMap: [String: String] = [:]
                var isInThePool: Bool = false
                
                if self.tx.coin.chain == .thorChain {
                    for pool in allPools {
                        let assetName = pool.asset
                        let cleanName = ThorchainService.cleanPoolName(assetName)
                        poolOptions.append(IdentifiableString(value: cleanName))
                        nameMap[cleanName] = assetName
                        
                        if let lastPart = cleanName
                            .uppercased()
                            .split(separator: ".")
                            .last {
                            if tx.coin.ticker.uppercased() == String(lastPart) {
                                isInThePool = true
                            }
                        }
                    }
                } else {
                    let currentSwap = self.tx.coin.chain.swapAsset.uppercased()
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
                        
                        if let lastPart = cleanName
                            .uppercased()
                            .split(separator: ".")
                            .last {
                            if tx.coin.ticker.uppercased() == String(lastPart) {
                                isInThePool = true
                            }
                        }
                    }
                }
                
                if tx.coin.ticker.uppercased() != "RUNE" && !isInThePool {
                    if let runeCoin = vault.runeCoin {
                        tx.coin = runeCoin
                    }
                }
                
                DispatchQueue.main.async {
                    self.poolNameMap = nameMap
                    self.availablePools = poolOptions
                    self.isLoadingPools = false
                    self.loadError = nil
                    
                    if self.tx.coin.chain != .thorChain && poolOptions.count == 1 {
                        self.selectedPool = poolOptions[0]
                        self.poolValid = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.availablePools = []
                    self.isLoadingPools = false
                    self.loadError = NSLocalizedString("failedToLoadPools", comment: "Failed to load pools error")
                }
            }
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
        
        if let assetCoin = vault.coins.first(where: { $0.chain == chainCoin.chain && $0.ticker.uppercased() == assetTicker }) {
            let balance = assetCoin.balanceDecimal.formatForDisplay()
            pairedAssetBalance = String(format: NSLocalizedString("balanceInParentheses", comment: ""), balance, assetCoin.ticker.uppercased())
        } else if assetTicker == chainPrefix {
            let balance = chainCoin.balanceDecimal.formatForDisplay()
            pairedAssetBalance = String(format: NSLocalizedString("balanceInParentheses", comment: ""), balance, chainCoin.ticker.uppercased())
        } else {
            pairedAssetBalance = "( \(assetTicker) not found in vault )"
        }
    }
    
    func updateSelectedPoolBalance(_ poolName: String) {
        if tx.coin.chain == .thorChain {
            selectedPoolBalance = balance  // RUNE
            return
        }
        
        let components = poolName.split(separator: ".").map { String($0).uppercased() }
        guard components.count >= 2 else {
            selectedPoolBalance = balance
            return
        }
        
        let chainPrefix = components[0]
        let assetTicker = components[1]
        
        // Todas as moedas da mesma chain
        let chainCoins = vault.coins.filter { $0.chain.swapAsset.uppercased() == chainPrefix }
        
        // 1. Verifica se é token nativo com o mesmo ticker
        if let native = chainCoins.first(where: { $0.isNativeToken && $0.ticker.uppercased() == assetTicker }) {
            selectedPoolBalance = formatBalance(native.balanceDecimal, ticker: native.ticker)
            return
        }
        
        // 2. Verifica se existe token com esse ticker
        if let token = chainCoins.first(where: { $0.ticker.uppercased() == assetTicker }) {
            selectedPoolBalance = formatBalance(token.balanceDecimal, ticker: token.ticker)
            return
        }
        
        // 3. Não encontrou
        selectedPoolBalance = "( \(assetTicker) not found in vault )"
    }
    
    func updateSelectedCoin(from poolName: String) {
        let components = poolName.split(separator: ".").map { String($0).uppercased() }
        guard components.count >= 2 else { return }
        
        let chainPrefix = components[0]
        let assetTicker = components[1]
        
        // Match correct coin in vault (native or token)
        if let coin = vault.coins.first(where: {
            $0.chain.swapAsset.uppercased() == chainPrefix &&
            $0.ticker.uppercased() == assetTicker
        }) {
            tx.coin = coin
        }
    }
    
    private func formatBalance(_ balance: Decimal, ticker: String) -> String {
        return String(format: NSLocalizedString("balanceInParentheses", comment: ""), balance.formatForDisplay(), ticker.uppercased())
    }
    
    private func setupValidation() {
        // Recompute amount validity when amount or selectedPool changes
        Publishers.CombineLatest($amount, $selectedPool)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] amount, _ in
                guard let self = self else { return }
                let currentBalance = self.tx.coin.balanceDecimal
                self.amountValid = amount > 0 && amount <= currentBalance
                
                if currentBalance < amount {
                    self.amountValid = false
                    self.customErrorMessage = NSLocalizedString("insufficientBalanceForFunctions", comment: "Error message when user tries to enter amount greater than available balance")
                } else {
                    self.customErrorMessage = nil
                }
            }
            .store(in: &cancellables)
        
        // Global form validity
        Publishers.CombineLatest3($amountValid, $pairedAddressValid, $poolValid)
            .map { $0 && $1 && $2 }
            .receive(on: DispatchQueue.main)
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
    
    func buildApprovePayload() -> ERC20ApprovePayload? {
        guard isApprovalRequired, !tx.toAddress.isEmpty else {
            return nil
        }
        return ERC20ApprovePayload(amount: tx.amountInRaw, spender: tx.toAddress)
    }
    
    var balance: String {
        let b = tx.coin.balanceDecimal.formatForDisplay()
        return String(format: NSLocalizedString("balanceInParentheses", comment: ""), b, tx.coin.ticker.uppercased())
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallAddThorLPView(model: self).onAppear {
            self.initialize()
        })
    }
    
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
                    .background(Theme.colors.bgSurface1.opacity(0.1))
                    .cornerRadius(10)
            }
            
            StyledFloatingPointField(
                label: {
                    // If adding RUNE (thorChain), show RUNE balance. Otherwise show the selected pool's asset balance.
                    if model.tx.coin.chain == .thorChain {
                        return "\(NSLocalizedString("amount", comment: "")) \(model.balance)"
                    } else if !model.selectedPoolBalance.isEmpty {
                        return "\(NSLocalizedString("amount", comment: "")) \(model.selectedPoolBalance)"
                    } else {
                        return "\(NSLocalizedString("amount", comment: "")) \(model.balance)"
                    }
                }(),
                placeholder: NSLocalizedString("enterAmount", comment: ""),
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
            } else if model.availablePools.isEmpty {
                errorView
            } else {
                dropdownView
            }
        }
    }
    
    private var loadingView: some View {
        HStack(spacing: 12) {
            Text(NSLocalizedString("loadingPools", comment: ""))
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
            
            Spacer()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.7)
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(10)
    }
    
    private var errorView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(Theme.fonts.bodyMRegular)
                    .foregroundColor(.orange)
                
                Text(model.loadError ?? NSLocalizedString("noPoolsAvailable", comment: ""))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textPrimary)
                    .lineLimit(2)
                
                Spacer()
                
                Button {
                    model.loadError = nil
                    model.isLoadingPools = true
                    model.loadPools()
                } label: {
                    Text(NSLocalizedString("retry", comment: ""))
                        .font(.caption)
                        .foregroundColor(Theme.colors.primaryAccent1)
                }
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(10)
        }
    }
    
    private var dropdownView: some View {
        GenericSelectorDropDown(
            items: .constant(model.availablePools),
            selected: Binding(get: { model.selectedPool }, set: { model.selectedPool = $0 }),
            mandatoryMessage: "*",
            descriptionProvider: { $0.value.isEmpty ? NSLocalizedString("selectPool", comment: "") : $0.value },
            onSelect: { pool in
                model.selectedPool = pool
                model.poolValid = !pool.value.isEmpty
                
                if !pool.value.isEmpty {
                    if model.tx.coin.chain == .thorChain {
                        model.prefillPairedAddressForPool(pool.value)
                    } else {
                        model.updateSelectedCoin(from: pool.value)
                        model.updateSelectedPoolBalance(pool.value)
                    }
                }
            }
            
        )
    }
}

struct ApprovalInfoSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("erc20ApprovalRequired", comment: ""))
                .font(Theme.fonts.bodyMMedium)
                .foregroundColor(Theme.colors.textPrimary)
            
            Text(NSLocalizedString("approvalRequiredMessageLP", comment: ""))
                .font(Theme.fonts.bodySRegular)
                .foregroundColor(Theme.colors.textPrimary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("approvalTransaction", comment: ""))
                    .font(Theme.fonts.caption12)
                    .foregroundColor(Theme.colors.primaryAccent1)
                Text(NSLocalizedString("addLiquidityTransaction", comment: ""))
                    .font(Theme.fonts.caption12)
                    .foregroundColor(Theme.colors.primaryAccent1)
            }
            .padding(.leading, 16)
        }
    }
}
