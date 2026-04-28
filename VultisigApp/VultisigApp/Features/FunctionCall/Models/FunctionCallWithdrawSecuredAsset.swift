//
//  FunctionCallWithdrawSecuredAsset.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 19/09/25.
//

import SwiftUI
import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "function-call-withdraw-secured-asset")

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
    @Published var minimumWithdrawAmount: Decimal = 0

    /// Maps a dropdown item's id to the underlying secured asset coin in the vault.
    private var securedAssetLookup: [UUID: Coin] = [:]
    /// Set by `updateDestinationAddress` when the vault lacks the L1 native
    /// coin; read by `updateErrorMessage` so destination issues take priority
    /// over amount/fee complaints.
    private var destinationError: String?

    private var cancellables = Set<AnyCancellable>()

    private static let thorChains: Set<Chain> = [.thorChain, .thorChainChainnet, .thorChainStagenet]

    // MARK: - Coin helpers

    private func nativeCoin(for chain: Chain) -> Coin? {
        vault.coins.first { $0.chain == chain && $0.isNativeToken }
    }

    private var thorNative: Coin? {
        vault.coins.first { Self.thorChains.contains($0.chain) && $0.isNativeToken }
    }

    /// Short symbol (e.g. "USDC") — `securedAssetSymbol` keeps the trailing
    /// contract suffix for signing, which isn't what we want for labels.
    private func shortSymbol(for coin: Coin) -> String {
        THORChainHelper.securedAssetSymbol(coin: coin)
            .split(separator: "-")
            .first
            .map(String.init) ?? coin.ticker.uppercased()
    }

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
        do {
            let assets = try await fetchSecuredAssetCoins()
            applyPicker(securedAssets: assets)
        } catch {
            logger.error("Failed to fetch THORChain balances: \(error.localizedDescription)")
            setPickerEmpty(reason: NSLocalizedString("noSecuredAssets", comment: ""))
        }
    }

    /// Pulls live cosmos-bank balances from the user's THOR address, persists
    /// any secured-asset denoms that aren't yet in the vault, and returns the
    /// set of coins with a non-zero balance sorted for display.
    ///
    /// Secured-asset balances live as cosmos-bank denoms and aren't present in
    /// `vault.coins` until explicitly enabled, so fetching from the network
    /// ensures USDC / USDT / WBTC etc. show up on first use. `addIfNeeded`
    /// skips the spam/hidden filters that `addDiscoveredTokens` would apply.
    @MainActor
    private func fetchSecuredAssetCoins() async throws -> [Coin] {
        guard let thorNative else { return [] }

        let service = ThorchainServiceFactory.getService(for: thorNative.chain)
        let balances = try await service.fetchBalances(thorNative.address)

        var persisted: [Coin] = []
        for balance in balances where Self.isSecuredDenom(balance.denom) {
            guard let coin = try persistSecuredAsset(balance: balance, chain: thorNative.chain) else {
                continue
            }
            coin.rawBalance = balance.amount
            persisted.append(coin)
        }

        return persisted
            .filter { $0.balanceDecimal > 0 }
            .sorted { displayName(for: $0) < displayName(for: $1) }
    }

    @MainActor
    private func applyPicker(securedAssets: [Coin]) {
        guard !securedAssets.isEmpty else {
            setPickerEmpty(reason: NSLocalizedString("noSecuredAssets", comment: ""))
            return
        }
        var assetList = [IdentifiableString(value: NSLocalizedString("selectSecuredAssetToWithdraw", comment: ""))]
        var lookup: [UUID: Coin] = [:]
        for coin in securedAssets {
            let item = IdentifiableString(value: displayName(for: coin))
            lookup[item.id] = coin
            assetList.append(item)
        }
        availableSecuredAssets = assetList
        securedAssetLookup = lookup
        loadError = nil
        isLoadingAssets = false
    }

    private static func isSecuredDenom(_ denom: String) -> Bool {
        let lower = denom.lowercased()
        guard lower != "rune" else { return false }
        guard !lower.hasPrefix("x/") else { return false }
        return lower.contains("-")
    }

    @MainActor
    private func persistSecuredAsset(balance: CosmosBalance, chain: Chain) throws -> Coin? {
        let info = THORChainTokenMetadataFactory.create(asset: balance.denom)
        let ticker = info.ticker.uppercased()
        let localAsset = TokensStore.TokenSelectionAssets.first {
            $0.ticker.caseInsensitiveCompare(ticker) == .orderedSame
        }
        let coinMeta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: localAsset?.logo ?? info.logo,
            decimals: info.decimals,
            priceProviderId: localAsset?.priceProviderId ?? "",
            contractAddress: balance.denom,
            isNativeToken: false
        )
        return try CoinService.addIfNeeded(asset: coinMeta, to: vault, priceProviderId: coinMeta.priceProviderId)
    }

    private func setPickerEmpty(reason: String) {
        availableSecuredAssets = [IdentifiableString(value: NSLocalizedString("selectSecuredAssetToWithdraw", comment: ""))]
        securedAssetLookup = [:]
        loadError = reason
        isLoadingAssets = false
    }

    /// Human-readable label for a secured asset (e.g. "ETH.USDC", "BTC.BTC").
    private func displayName(for coin: Coin) -> String {
        "\(THORChainHelper.securedAssetChain(coin: coin)).\(shortSymbol(for: coin))"
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

        Task { @MainActor in
            await refreshOutboundFeeThreshold(for: securedAssetCoin)
        }
    }

    /// Queries the L1 chain's outbound_fee from THORChain's inbound_addresses and
    /// converts it into the selected secured asset's units so we can reject
    /// amounts THORChain would refuse with "not enough asset to pay for fees".
    @MainActor
    private func refreshOutboundFeeThreshold(for securedAssetCoin: Coin) async {
        minimumWithdrawAmount = 0

        let l1ChainCode = THORChainHelper.securedAssetChain(coin: securedAssetCoin)
        guard let l1Chain = chain(forSwapAsset: l1ChainCode),
              let native = nativeCoin(for: l1Chain) else {
            return
        }

        let inboundChainName = ThorchainService.getInboundChainName(for: l1Chain)
        let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
        guard let inbound = addresses.first(where: { $0.chain.uppercased() == inboundChainName.uppercased() }),
              let feeRaw = inbound.outbound_fee,
              let feeBaseUnits = Decimal(string: feeRaw) else {
            return
        }

        // outbound_fee is denominated in the L1 native asset at 8 decimals across
        // all THORChain-supported chains.
        let feeNativeAmount = feeBaseUnits / pow(10, 8)
        let feeFiat = RateProvider.shared.fiatBalance(value: feeNativeAmount, coin: native)
        let unitFiat = RateProvider.shared.fiatBalance(value: 1, coin: securedAssetCoin)

        guard feeFiat > 0, unitFiat > 0 else {
            return
        }

        // Small buffer so a price tick between check and broadcast doesn't flip
        // the tx from accepted to "not enough asset to pay for fees".
        let buffer: Decimal = 1.2
        minimumWithdrawAmount = (feeFiat * buffer) / unitFiat
        validateAmount()
    }

    private func updateDestinationAddress(for securedAssetCoin: Coin) {
        // The L1 chain is encoded in the secured asset's denom (e.g. "eth-usdc-0x...").
        let l1Chain = THORChainHelper.securedAssetChain(coin: securedAssetCoin)
        let targetChain = chain(forSwapAsset: l1Chain)

        if let targetChain, let coin = nativeCoin(for: targetChain) {
            destinationAddress = coin.address
            destinationAddressValid = true
            destinationError = nil
        } else {
            destinationAddress = ""
            destinationAddressValid = false
            let chainName = targetChain?.name ?? l1Chain
            destinationError = String(
                format: NSLocalizedString("withdrawSecuredAssetError", comment: ""),
                shortSymbol(for: securedAssetCoin),
                l1Chain,
                chainName
            )
        }
        updateErrorMessage()
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
        amountValid = computeAmountValid()
        updateErrorMessage()
    }

    private func computeAmountValid() -> Bool {
        guard amount > 0, let secured = selectedSecuredAssetCoin else { return false }
        guard amount <= secured.balanceDecimal else { return false }
        if minimumWithdrawAmount > 0, amount < minimumWithdrawAmount { return false }
        return true
    }

    /// Destination errors take priority over amount/fee errors — matches the
    /// original behavior that suppressed amount messages while destination was
    /// broken, but without scattering `customErrorMessage` writes across three
    /// methods.
    private func updateErrorMessage() {
        customErrorMessage = destinationError ?? amountErrorMessage()
    }

    private func amountErrorMessage() -> String? {
        guard destinationAddressValid else { return nil }
        guard amount > 0 else {
            return NSLocalizedString("enterValidAmount", comment: "")
        }
        guard let secured = selectedSecuredAssetCoin else {
            return NSLocalizedString("selectSecuredAssetToSeeBalance", comment: "")
        }
        if amount > secured.balanceDecimal {
            return NSLocalizedString("insufficientBalanceForFunctions", comment: "")
        }
        if minimumWithdrawAmount > 0, amount < minimumWithdrawAmount {
            return String(
                format: NSLocalizedString("withdrawBelowOutboundFee", comment: ""),
                minimumWithdrawAmount.formatForDisplay(),
                secured.ticker.uppercased()
            )
        }
        return nil
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
