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

    /// Maps a dropdown item's id to the underlying secured asset coin in the vault.
    private var securedAssetLookup: [UUID: Coin] = [:]

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
        Task { @MainActor in
            await loadAvailableSecuredAssets()
        }
    }

    private func prefillAddresses() {
        // For withdraw, prefill with the original coin's address as destination
        destinationAddress = tx.coin.address
        destinationAddressValid = !destinationAddress.isEmpty
    }

    // MARK: - Load Available Secured Assets

    @MainActor
    func loadAvailableSecuredAssets() async {
        isLoadingAssets = true
        loadError = nil

        // Secured-asset balances live as cosmos-bank denoms on the user's THOR
        // address, not as entries in `vault.coins` until a discovery pass
        // persists them. Trigger the same discovery path the chain detail
        // screen uses so USDC / USDT / etc. acquired after the last visit are
        // picked up before we build the dropdown.
        let thorChains: Set<Chain> = [.thorChain, .thorChainChainnet, .thorChainStagenet]
        let thorNative = vault.coins.first { coin in
            thorChains.contains(coin.chain) && coin.isNativeToken
        }
        if let thorNative {
            await CoinService.addDiscoveredTokens(nativeToken: thorNative, to: vault)
        }

        // A secured asset is any non-native THORChain coin whose on-chain denom is
        // formatted as `<l1chain>-<symbol>[-<contract>]` (see THORChainHelper).
        let securedAssetsInVault = vault.coins
            .filter { THORChainHelper.isSecuredAsset(coin: $0) && $0.balanceDecimal > 0 }
            .sorted { displayName(for: $0) < displayName(for: $1) }

        var assetList = [IdentifiableString(value: NSLocalizedString("selectSecuredAssetToWithdraw", comment: ""))]
        var lookup: [UUID: Coin] = [:]

        if securedAssetsInVault.isEmpty {
            availableSecuredAssets = assetList
            securedAssetLookup = lookup
            loadError = NSLocalizedString("noSecuredAssets", comment: "")
        } else {
            let vaultAssets = securedAssetsInVault.map { coin -> IdentifiableString in
                let item = IdentifiableString(value: displayName(for: coin))
                lookup[item.id] = coin
                return item
            }
            assetList.append(contentsOf: vaultAssets)
            availableSecuredAssets = assetList
            securedAssetLookup = lookup
            loadError = nil
        }
        isLoadingAssets = false
    }

    /// Human-readable label for a secured asset (e.g. "ETH.USDC", "BTC.BTC").
    /// Uses the L1 chain + symbol (without the trailing contract address suffix
    /// that `securedAssetSymbol` preserves) so labels stay short and unique.
    private func displayName(for coin: Coin) -> String {
        let chain = THORChainHelper.securedAssetChain(coin: coin)
        let symbol = THORChainHelper.securedAssetSymbol(coin: coin)
            .split(separator: "-")
            .first
            .map(String.init) ?? coin.ticker.uppercased()
        return "\(chain).\(symbol)"
    }

    // MARK: - Asset Selection

    func selectSecuredAsset(_ asset: IdentifiableString) {
        selectedSecuredAsset = asset

        // Check if it's the placeholder option
        if asset.value == Self.INITIAL_ITEM_FOR_DROPDOWN_TEXT {
            securedAssetValid = false
            destinationAddress = ""
            destinationAddressValid = false
            selectedSecuredAssetCoin = nil
            return
        }

        // Resolve the underlying secured asset coin via the stable id mapping so
        // tokens that share a symbol across chains (e.g. USDC on ETH vs AVAX) stay
        // addressable independently.
        guard let securedAssetCoin = securedAssetLookup[asset.id] else {
            securedAssetValid = false
            selectedSecuredAssetCoin = nil
            return
        }

        securedAssetValid = true

        // Update the tx.coin to the selected secured asset for balance validation
        updateTxCoin(for: securedAssetCoin)

        // Update destination address based on the L1 chain encoded in the denom
        updateDestinationAddress(for: securedAssetCoin)
    }

    private func updateDestinationAddress(for securedAssetCoin: Coin) {
        // The L1 chain is encoded in the secured asset's denom (e.g. "eth-usdc-0x...").
        let l1Chain = THORChainHelper.securedAssetChain(coin: securedAssetCoin)
        let displayTicker = displayName(for: securedAssetCoin)
            .split(separator: ".")
            .last
            .map(String.init) ?? securedAssetCoin.ticker.uppercased()
        let targetChain = chain(forSwapAsset: l1Chain)

        // Find the corresponding native coin in vault to get the user's own address for that chain
        if let targetChain,
           let coin = vault.coins.first(where: { $0.chain == targetChain && $0.isNativeToken }) {
            destinationAddress = coin.address
            destinationAddressValid = true
            customErrorMessage = nil
        } else {
            // If no coin exists for that chain in the vault, show error
            destinationAddress = ""
            destinationAddressValid = false
            let chainName = targetChain?.name ?? l1Chain
            customErrorMessage = String(
                format: NSLocalizedString("withdrawSecuredAssetError", comment: ""),
                displayTicker,
                l1Chain,
                chainName
            )
        }
    }

    /// Maps a THORChain swap-asset chain code (e.g. "ETH", "AVAX") to the local `Chain` enum.
    private func chain(forSwapAsset swapAsset: String) -> Chain? {
        Chain.allCases.first { $0.swapAsset.uppercased() == swapAsset.uppercased() }
    }

    private func updateTxCoin(for securedAssetCoin: Coin) {
        selectedSecuredAssetCoin = securedAssetCoin

        // Ensure isNativeToken is false for secured assets so getTicker() routes
        // through getNotNativeTicker() which handles secured assets correctly.
        securedAssetCoin.isNativeToken = false

        tx.coin = securedAssetCoin
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
                    Task { await model.loadAvailableSecuredAssets() }
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
