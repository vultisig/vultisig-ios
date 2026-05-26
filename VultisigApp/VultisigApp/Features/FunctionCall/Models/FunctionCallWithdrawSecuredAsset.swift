//
//  FunctionCallWithdrawSecuredAsset.swift
//  VultisigApp
//
//  SECURE+ withdraw sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — drops `FunctionCallAddressable` and
//  `getView() -> AnyView`. Owns its own typed state (no shared form
//  scratchpad). Cross-mutator: the secured-asset picker writes the
//  screen-owned `selectedCoin` via `coinSelectionHandler` so the new
//  asset's balance + chain inform gas refresh.
//

import BigInt
import Combine
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "function-call-withdraw-secured-asset")

@Observable
@MainActor
final class FunctionCallWithdrawSecuredAsset {

    static let initialItemForDropdownText: String = "selectSecuredAssetToWithdraw".localized

    var amount: Decimal = 0.0
    var destinationAddress: String = ""
    var selectedSecuredAsset: IdentifiableString

    var availableSecuredAssets: [IdentifiableString] = []
    var isLoadingAssets: Bool = true
    var loadError: String?
    var selectedSecuredAssetCoin: Coin?
    var minimumWithdrawAmount: Decimal = 0
    var customErrorMessage: String?

    /// Current source coin — initially the screen's `selectedCoin`,
    /// then overwritten when the secured-asset picker fires.
    var coin: Coin

    @ObservationIgnored private var securedAssetLookup: [UUID: Coin] = [:]
    @ObservationIgnored private var destinationError: String?
    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private var loadingTasks: [Task<Void, Never>] = []
    @ObservationIgnored var coinSelectionHandler: ((Coin) -> Void)?

    private static let thorChains: Set<Chain> = [.thorChain, .thorChainChainnet, .thorChainStagenet]

    init(coin: Coin, vault: Vault) {
        self.coin = coin
        self.vault = vault
        self.selectedSecuredAsset = .init(value: "selectSecuredAssetToWithdraw".localized)
    }

    deinit {
        loadingTasks.forEach { $0.cancel() }
    }

    func initialize() {
        prefillAddresses()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadAvailableSecuredAssets()
        }
        loadingTasks.append(task)
    }

    private func prefillAddresses() {
        destinationAddress = coin.address
    }

    private func nativeCoin(for chain: Chain) -> Coin? {
        vault.coins.first { $0.chain == chain && $0.isNativeToken }
    }

    private var thorNative: Coin? {
        vault.coins.first { Self.thorChains.contains($0.chain) && $0.isNativeToken }
    }

    private func shortSymbol(for coin: Coin) -> String {
        THORChainHelper.securedAssetSymbol(coin: coin)
            .split(separator: "-")
            .first
            .map(String.init) ?? coin.ticker.uppercased()
    }

    func loadAvailableSecuredAssets() async {
        isLoadingAssets = true
        loadError = nil
        do {
            let assets = try await fetchSecuredAssetCoins()
            applyPicker(securedAssets: assets)
        } catch {
            logger.error("Failed to fetch THORChain balances: \(error.localizedDescription)")
            setPickerEmpty(reason: "noSecuredAssets".localized)
        }
    }

    private func fetchSecuredAssetCoins() async throws -> [Coin] {
        guard let thorNative else { return [] }
        let service = ThorchainServiceFactory.getService(for: thorNative.chain)
        let balances = try await service.fetchBalances(thorNative.address)

        var persisted: [Coin] = []
        for balance in balances where Self.isSecuredDenom(balance.denom) {
            guard let coin = try persistSecuredAsset(balance: balance, chain: thorNative.chain) else { continue }
            coin.rawBalance = balance.amount
            persisted.append(coin)
        }
        return persisted
            .filter { $0.balanceDecimal > 0 }
            .sorted { displayName(for: $0) < displayName(for: $1) }
    }

    private func applyPicker(securedAssets: [Coin]) {
        guard !securedAssets.isEmpty else {
            setPickerEmpty(reason: "noSecuredAssets".localized)
            return
        }
        var assetList = [IdentifiableString(value: "selectSecuredAssetToWithdraw".localized)]
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
        availableSecuredAssets = [IdentifiableString(value: "selectSecuredAssetToWithdraw".localized)]
        securedAssetLookup = [:]
        loadError = reason
        isLoadingAssets = false
    }

    private func displayName(for coin: Coin) -> String {
        "\(THORChainHelper.securedAssetChain(coin: coin)).\(shortSymbol(for: coin))"
    }

    func selectSecuredAsset(_ asset: IdentifiableString) {
        selectedSecuredAsset = asset

        if asset.value == Self.initialItemForDropdownText {
            destinationAddress = ""
            selectedSecuredAssetCoin = nil
            return
        }

        guard let securedAssetCoin = securedAssetLookup[asset.id] else {
            selectedSecuredAssetCoin = nil
            return
        }

        updateTxCoin(for: securedAssetCoin)
        updateDestinationAddress(for: securedAssetCoin)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshOutboundFeeThreshold(for: securedAssetCoin)
        }
        loadingTasks.append(task)
    }

    private func refreshOutboundFeeThreshold(for securedAssetCoin: Coin) async {
        minimumWithdrawAmount = 0

        let l1ChainCode = THORChainHelper.securedAssetChain(coin: securedAssetCoin)
        guard let l1Chain = chain(forSwapAsset: l1ChainCode),
              let native = nativeCoin(for: l1Chain) else { return }

        let inboundChainName = ThorchainService.getInboundChainName(for: l1Chain)
        let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()
        guard let inbound = addresses.first(where: { $0.chain.uppercased() == inboundChainName.uppercased() }),
              let feeRaw = inbound.outbound_fee,
              let feeBaseUnits = Decimal(string: feeRaw) else { return }

        let feeNativeAmount = feeBaseUnits / pow(10, 8)
        let feeFiat = RateProvider.shared.fiatBalance(value: feeNativeAmount, coin: native)
        let unitFiat = RateProvider.shared.fiatBalance(value: 1, coin: securedAssetCoin)

        guard feeFiat > 0, unitFiat > 0 else { return }

        let buffer: Decimal = 1.2
        minimumWithdrawAmount = (feeFiat * buffer) / unitFiat
        updateErrorMessage()
    }

    private func updateDestinationAddress(for securedAssetCoin: Coin) {
        let l1Chain = THORChainHelper.securedAssetChain(coin: securedAssetCoin)
        let targetChain = chain(forSwapAsset: l1Chain)

        if let targetChain, let coin = nativeCoin(for: targetChain) {
            destinationAddress = coin.address
            destinationError = nil
        } else {
            destinationAddress = ""
            let chainName = targetChain?.name ?? l1Chain
            destinationError = String(
                format: "withdrawSecuredAssetError".localized,
                shortSymbol(for: securedAssetCoin),
                l1Chain,
                chainName
            )
        }
        updateErrorMessage()
    }

    private func chain(forSwapAsset swapAsset: String) -> Chain? {
        Chain.allCases.first { $0.swapAsset.uppercased() == swapAsset.uppercased() }
    }

    private func updateTxCoin(for securedAssetCoin: Coin) {
        selectedSecuredAssetCoin = securedAssetCoin
        securedAssetCoin.isNativeToken = false
        coin = securedAssetCoin
        coinSelectionHandler?(securedAssetCoin)
    }

    var isAmountValid: Bool {
        guard amount > 0, let secured = selectedSecuredAssetCoin else { return false }
        guard amount <= secured.balanceDecimal else { return false }
        if minimumWithdrawAmount > 0, amount < minimumWithdrawAmount { return false }
        return true
    }

    var isSecuredAssetValid: Bool {
        selectedSecuredAsset.value != Self.initialItemForDropdownText && selectedSecuredAssetCoin != nil
    }

    var isDestinationAddressValid: Bool {
        !destinationAddress.isEmpty && destinationAddress.count > 10
    }

    var isTheFormValid: Bool {
        isAmountValid && isDestinationAddressValid && isSecuredAssetValid
    }

    func validateAmount() {
        updateErrorMessage()
    }

    private func updateErrorMessage() {
        customErrorMessage = destinationError ?? amountErrorMessage()
    }

    private func amountErrorMessage() -> String? {
        guard isDestinationAddressValid else { return nil }
        guard amount > 0 else { return "enterValidAmount".localized }
        guard let secured = selectedSecuredAssetCoin else {
            return "selectSecuredAssetToSeeBalance".localized
        }
        if amount > secured.balanceDecimal {
            return "insufficientBalanceForFunctions".localized
        }
        if minimumWithdrawAmount > 0, amount < minimumWithdrawAmount {
            return String(
                format: "withdrawBelowOutboundFee".localized,
                minimumWithdrawAmount.formatForDisplay(),
                secured.ticker.uppercased()
            )
        }
        return nil
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        "SECURE-:\(destinationAddress)"
    }

    var balance: String {
        if selectedSecuredAsset.value.isEmpty || selectedSecuredAsset.value == Self.initialItemForDropdownText {
            return "selectAssetToSeeBalance".localized
        }
        if let securedAsset = selectedSecuredAssetCoin {
            let b = securedAsset.balanceDecimal.formatForDisplay()
            return String(format: "balanceInParentheses".localized, b, selectedSecuredAsset.value)
        }
        return String(format: "balanceInParentheses".localized, "0", selectedSecuredAsset.value)
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("operation", "withdraw")
        dict.set("memo", toString())
        dict.set("destinationAddress", destinationAddress)
        return dict
    }

    func getAssetTicker() -> String {
        selectedSecuredAsset.value.isEmpty ? Self.initialItemForDropdownText : selectedSecuredAsset.value
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        _ = isFastVault
        return SendTransaction.empty(coin: coin, vault: vault).copy(
            // Withdraw is done via MsgDeposit on THORChain — toAddress
            // intentionally empty (matches `FunctionCallInstance.toAddress`
            // returning nil for `.withdrawSecuredAsset`).
            toAddress: "",
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .unspecified,
            memoFunctionDictionary: toDictionary().allItems(),
            wasmContractPayload: .set(nil)
        )
    }
}

// MARK: - Views

struct WithdrawSecuredAssetFormView: View {
    @Bindable var model: FunctionCallWithdrawSecuredAsset
    @Binding var selectedCoin: Coin

    var body: some View {
        VStack(spacing: 16) {
            SecuredAssetSelectorSection(model: model)

            if model.selectedSecuredAsset.value != FunctionCallWithdrawSecuredAsset.initialItemForDropdownText {
                AmountInputSection(model: model)
            }
        }
        .onAppear {
            model.coinSelectionHandler = { coin in
                selectedCoin = coin
            }
            model.initialize()
        }
    }
}

struct SecuredAssetSelectorSection: View {
    @Bindable var model: FunctionCallWithdrawSecuredAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isLoadingAssets {
                loadingView
            } else if model.availableSecuredAssets.isEmpty {
                errorView
            } else {
                dropdownView

                if let errorMessage = model.customErrorMessage,
                   model.selectedSecuredAsset.value != FunctionCallWithdrawSecuredAsset.initialItemForDropdownText {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var loadingView: some View {
        HStack(spacing: 12) {
            Text("loadingSecuredAssets".localized)
                .font(.body)
                .foregroundStyle(.primary)

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
                    .foregroundStyle(.orange)

                Text(model.loadError ?? "noSecuredAssetsAvailable".localized)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer()

                Button {
                    Task { await model.loadAvailableSecuredAssets() }
                } label: {
                    Text("retry".localized)
                        .font(.caption)
                        .foregroundStyle(.blue)
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
            selected: $model.selectedSecuredAsset,
            mandatoryMessage: "*",
            descriptionProvider: { $0.value },
            onSelect: { asset in
                model.selectSecuredAsset(asset)
            }
        )
    }
}

struct AmountInputSection: View {
    @Bindable var model: FunctionCallWithdrawSecuredAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StyledFloatingPointField(
                label: "amountToWithdraw".localized,
                placeholder: "enterAmount".localized,
                value: $model.amount,
                isValid: .constant(true)
            )
            .onChange(of: model.amount) {
                model.validateAmount()
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
    }
}
