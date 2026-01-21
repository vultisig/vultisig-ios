//
//  FunctionCallWithdrawSecuredAsset.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 19/09/25.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Main ViewModel

class FunctionCallWithdrawSecuredAsset: FunctionCallAddressable, ObservableObject {
    
    static let INITIAL_ITEM_FOR_DROPDOWN_TEXT: String = NSLocalizedString("selectSecuredAssetToWithdraw", comment: "")
    
    @Published var isTheFormValid: Bool = false
    @Published var customErrorMessage: String? = nil
    @Published var amount: Decimal = 0.0
    @Published var destinationAddress: String = ""
    @Published var selectedSecuredAsset: IdentifiableString = .init(value: NSLocalizedString("selectSecuredAssetToWithdraw", comment: ""))
    
    @Published var amountValid: Bool = false
    @Published var destinationAddressValid: Bool = false
    @Published var securedAssetValid: Bool = false
    
    @Published var availableSecuredAssets: [IdentifiableString] = []
    @Published var isLoadingAssets: Bool = true
    @Published var loadError: String? = nil
    @Published var selectedSecuredAssetCoin: Coin? = nil  // Track the actual secured asset coin
    
    private var cancellables = Set<AnyCancellable>()
    
    // Domain models
    var tx: SendTransaction
    private var vault: Vault
    
    var addressFields: [String: String] {
        get { 
            ["destinationAddress": destinationAddress]
        }
        set {
            if let v = newValue["destinationAddress"] {
                destinationAddress = v
            }
        }
    }
    
    required init(tx: SendTransaction, vault: Vault) {
        self.tx = tx
        self.vault = vault
        
        // For withdraw, tx.coin will be set to the selected secured asset
        // when user selects from dropdown. Don't set it to RUNE here.
    }
    
    func initialize() {
        setupValidation()
        prefillAddresses()
        loadAvailableSecuredAssets()
    }
    
    private func prefillAddresses() {
        // For withdraw, prefill with the original coin's address as destination
        destinationAddress = tx.coin.address
        destinationAddressValid = !destinationAddress.isEmpty
    }
    
    // MARK: - Load Available Secured Assets
    
    func loadAvailableSecuredAssets() {
        isLoadingAssets = true
        loadError = nil
        
        // Supported secured asset tickers
        let supportedTickers = ["BTC", "ETH", "BCH", "LTC", "DOGE", "AVAX", "BNB"]
        
        // Get secured assets that actually exist in the vault
        // They might be stored as "DOGE" or "DOGE-DOGE" format
        let securedAssetsInVault = vault.coins.filter { coin in
            guard coin.chain == .thorChain && coin.balanceDecimal > 0 else { return false }
            
            let ticker = coin.ticker.uppercased()
            // Check if it matches a supported ticker directly (e.g., "DOGE")
            if supportedTickers.contains(ticker) {
                return true
            }
            // Check if it's in dash format (e.g., "DOGE-DOGE")
            for supported in supportedTickers {
                if ticker == "\(supported)-\(supported)" {
                    return true
                }
            }
            return false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            
            // Always start with "Select asset" placeholder to ensure dropdown works
            var assetList = [IdentifiableString(value: NSLocalizedString("selectSecuredAssetToWithdraw", comment: ""))]
            
            if securedAssetsInVault.isEmpty {
                // Keep just the placeholder
                self.availableSecuredAssets = assetList
                self.loadError = NSLocalizedString("noSecuredAssets", comment: "")
            } else {
                
                let vaultAssets = securedAssetsInVault.map { coin in
                    let ticker = coin.ticker.uppercased()
                    
                    if ticker.contains("-") {
                        let parts = ticker.split(separator: "-")
                        if parts.count == 2 && parts[0] == parts[1] {
                            return IdentifiableString(value: String(parts[0]))
                        }
                    }
                    // Otherwise use the ticker as is
                    return IdentifiableString(value: coin.ticker)
                }
                assetList.append(contentsOf: vaultAssets)
                self.availableSecuredAssets = assetList
                self.loadError = nil
            }
            self.isLoadingAssets = false
        }
    }
    
    // MARK: - Asset Selection
    
    func selectSecuredAsset(_ asset: IdentifiableString) {
        selectedSecuredAsset = asset
        
        // Check if it's the placeholder option
        if asset.value == Self.INITIAL_ITEM_FOR_DROPDOWN_TEXT {
            securedAssetValid = false
            destinationAddress = ""
            destinationAddressValid = false
            return
        }
        
        // Valid asset selected
        securedAssetValid = true
        
        // Update destination address based on selected asset
        updateDestinationAddressForAsset(asset.value)
        
        // Update the tx.coin to the selected secured asset for balance validation
        updateTxCoinForSelectedAsset(asset.value)
    }
    
    private func updateDestinationAddressForAsset(_ assetName: String) {
        // assetName is just the ticker (e.g., "BTC", "ETH", "DOGE")
        let ticker = assetName.uppercased()
        
        // Map secured asset ticker to its native chain
        // When withdrawing, we need to send to the original chain address
        let targetChain = getChainForSecuredAsset(ticker)
        
        // Find the corresponding native coin in vault to get the user's own address for that chain
        if let coin = vault.coins.first(where: { 
            $0.chain == targetChain && $0.isNativeToken
        }) {
            destinationAddress = coin.address
            destinationAddressValid = true
            customErrorMessage = nil
        } else {
            // If no coin exists for that chain in the vault, show error
            destinationAddress = ""
            destinationAddressValid = false
            customErrorMessage = String(format: NSLocalizedString("withdrawSecuredAssetError", comment: ""), ticker, ticker, targetChain.name)
        }
    }
    
    /// Maps a secured asset ticker to its native blockchain chain
    private func getChainForSecuredAsset(_ ticker: String) -> Chain {
        switch ticker.uppercased() {
        case "BTC":
            return .bitcoin
        case "ETH":
            return .ethereum
        case "BCH":
            return .bitcoinCash
        case "LTC":
            return .litecoin
        case "DOGE":
            return .dogecoin
        case "AVAX":
            return .avalanche
        case "BNB":
            return .bscChain
        default:
            // Fallback to THORChain if unknown (shouldn't happen)
            return .thorChain
        }
    }
    
    private func updateTxCoinForSelectedAsset(_ assetName: String) {
        // assetName is just the ticker (e.g., "BTC", "ETH", "DOGE")
        let ticker = assetName.uppercased()
        
        // Find the secured asset coin - it could be stored as "DOGE" or "DOGE-DOGE"
        if let securedAssetCoin = vault.coins.first(where: {
            guard $0.chain == .thorChain else { return false }
            let coinTicker = $0.ticker.uppercased()
            // Check if it matches the ticker directly or in the "TICKER-TICKER" format
            return coinTicker == ticker || coinTicker == "\(ticker)-\(ticker)"
        }) {
            selectedSecuredAssetCoin = securedAssetCoin
            
            // Set the coin and ensure isNativeToken is false for secured assets
            // This will make getTicker() use getNotNativeTicker() which handles secured assets correctly
            let correctedCoin = securedAssetCoin
            correctedCoin.isNativeToken = false
            
            tx.coin = correctedCoin
        } else {
            selectedSecuredAssetCoin = nil
        }
    }
    
    private func setupValidation() {
        $amount
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.validateAmount()
            }
            .store(in: &cancellables)
        
        $destinationAddress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] address in
                self?.destinationAddressValid = !address.isEmpty && address.count > 10
            }
            .store(in: &cancellables)
        
        Publishers.CombineLatest3($amountValid, $destinationAddressValid, $securedAssetValid)
            .map { amountValid, destinationAddressValid, securedAssetValid in
                return amountValid && destinationAddressValid && securedAssetValid
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.isTheFormValid, on: self)
            .store(in: &cancellables)
    }
    
    private func validateAmount() {
        guard amount > 0 else {
            amountValid = false
            // Only set amount error if there's no destination address error
            if destinationAddressValid {
                customErrorMessage = NSLocalizedString("enterValidAmount", comment: "")
            }
            return
        }
        
        if let secured = selectedSecuredAssetCoin {
            amountValid = amount <= secured.balanceDecimal
            // Only update error message if there's no destination address error
            if destinationAddressValid {
                customErrorMessage = amountValid ? nil : NSLocalizedString("insufficientBalanceForFunctions", comment: "")
            }
        } else {
            amountValid = false
            // Only set this error if there's no destination address error
            if destinationAddressValid {
                customErrorMessage = NSLocalizedString("selectSecuredAssetToSeeBalance", comment: "")
            }
        }
    }
    
    var description: String {
        return toString()
    }
    
    func toString() -> String {
        return "SECURE-:\(destinationAddress)"
    }
    
    var balance: String {
        if selectedSecuredAsset.value.isEmpty || selectedSecuredAsset.value == Self.INITIAL_ITEM_FOR_DROPDOWN_TEXT {
            return NSLocalizedString("selectAssetToSeeBalance", comment: "")
        }
        
        // Use the selectedSecuredAssetCoin which contains the actual secured asset
        if let securedAsset = selectedSecuredAssetCoin {
            let b = securedAsset.balanceDecimal.formatForDisplay()
            return String(format: NSLocalizedString("balanceInParentheses", comment: ""), b, selectedSecuredAsset.value)
        } else {
            return String(format: NSLocalizedString("balanceInParentheses", comment: ""), "0", selectedSecuredAsset.value)
        }
    }
    
    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("operation", "withdraw")
        dict.set("memo", toString())
        dict.set("destinationAddress", destinationAddress)
        return dict
    }
    
    func getView() -> AnyView {
        AnyView(FunctionCallWithdrawSecuredAssetView(model: self).onAppear {
            self.initialize()
        })
    }
}

// MARK: - SwiftUI Views

struct FunctionCallWithdrawSecuredAssetView: View {
    @ObservedObject var model: FunctionCallWithdrawSecuredAsset
    
    var body: some View {
        VStack(spacing: 16) {
            SecuredAssetSelectorSection(model: model)
            
            if model.selectedSecuredAsset.value != FunctionCallWithdrawSecuredAsset.INITIAL_ITEM_FOR_DROPDOWN_TEXT {
                AmountInputSection(model: model)
            }
        }
    }
}

struct SecuredAssetSelectorSection: View {
    @ObservedObject var model: FunctionCallWithdrawSecuredAsset
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isLoadingAssets {
                loadingView
            } else if model.availableSecuredAssets.isEmpty {
                errorView
            } else {
                dropdownView
                
                // Show error if coin for selected asset is not in vault
                if let errorMessage = model.customErrorMessage, 
                   model.selectedSecuredAsset.value != FunctionCallWithdrawSecuredAsset.INITIAL_ITEM_FOR_DROPDOWN_TEXT {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
        }
    }
    
    private var loadingView: some View {
        HStack(spacing: 12) {
            Text(NSLocalizedString("loadingSecuredAssets", comment: ""))
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.7)
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var errorView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.body)
                    .foregroundColor(.orange)
                
                Text(model.loadError ?? NSLocalizedString("noSecuredAssetsAvailable", comment: ""))
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Spacer()
                
                Button {
                    model.loadError = nil
                    model.isLoadingAssets = true
                    model.loadAvailableSecuredAssets()
                } label: {
                    Text(NSLocalizedString("retry", comment: ""))
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    private var dropdownView: some View {
        GenericSelectorDropDown(
            items: .constant(model.availableSecuredAssets),
            selected: Binding(
                get: { model.selectedSecuredAsset },
                set: { model.selectedSecuredAsset = $0 }
            ),
            mandatoryMessage: "*",
            descriptionProvider: { $0.value },
            onSelect: { asset in
                model.selectSecuredAsset(asset)
            }
        )
    }
}

struct AmountInputSection: View {
    @ObservedObject var model: FunctionCallWithdrawSecuredAsset
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StyledFloatingPointField(
                label: NSLocalizedString("amountToWithdraw", comment: ""),
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
    }
}

extension FunctionCallWithdrawSecuredAsset {
    func getAssetTicker() -> String {
        return selectedSecuredAsset.value.isEmpty ? Self.INITIAL_ITEM_FOR_DROPDOWN_TEXT : selectedSecuredAsset.value
    }
}
