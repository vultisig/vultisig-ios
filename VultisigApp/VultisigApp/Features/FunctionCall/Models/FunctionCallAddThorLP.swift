//
//  FunctionCallAddThorLP.swift
//  VultisigApp
//
//  THORChain LP add sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — drops `FunctionCallAddressable` and
//  `getView() -> AnyView`, exposes `toSendTransaction(...)` at the
//  navigation boundary, and co-locates the
//  `AddThorLPFormView` partner in this file. Cross-mutator: writes the
//  screen-owned `selectedCoin` from the paired-token-pool dropdown.
//
//  Owns its own typed state: source coin, inbound-router address, and
//  amount drive the ERC20 approve payload directly. No shared form
//  scratchpad — callers go through `toSendTransaction(...)` /
//  `buildApprovePayload()`.
//

import BigInt
import Combine
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "function-call-add-thor-lp")

@Observable
@MainActor
final class FunctionCallAddThorLP {
    var amount: Decimal = 0.0
    var pairedAddress: String = ""
    var selectedPool: IdentifiableString = .init(value: "")
    var customErrorMessage: String?

    var availablePools: [IdentifiableString] = []
    var isLoadingPools: Bool = true
    var loadError: String?

    @ObservationIgnored private var poolNameMap: [String: String] = [:]
    var pairedAssetBalance: String = ""
    var selectedPoolBalance: String = ""

    var isApprovalRequired: Bool = false
    var approvePayload: ERC20ApprovePayload?

    var isEnablingThorchain: Bool = false

    /// THORChain inbound address — router for ERC20, vault address
    /// otherwise. Set by `fetchInboundAddressAndSetupApproval()` once
    /// resolved. Read by `FunctionCallInstance.toAddress` for downstream
    /// signing.
    var toAddress: String = ""

    /// Source coin — owned by this sub-model. Mutated when the
    /// pool-dropdown selects a paired chain coin or RUNE-pin fires.
    var coin: Coin

    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private var loadingTasks: [Task<Void, Never>] = []
    @ObservationIgnored var coinSelectionHandler: ((Coin) -> Void)?

    init(coin: Coin, vault: Vault) {
        self.coin = coin
        self.vault = vault
    }

    deinit {
        loadingTasks.forEach { $0.cancel() }
    }

    var isThorchainEnabled: Bool {
        vault.coins.contains { $0.chain == .thorChain && $0.isNativeToken }
    }

    func initialize() {
        prefillPairedAddress()
        loadInitialState()
    }

    func enableThorchain() async {
        guard !isEnablingThorchain, !isThorchainEnabled else { return }
        guard let runeMeta = TokensStore.TokenSelectionAssets.first(where: {
            $0.chain == .thorChain && $0.isNativeToken
        }) else { return }

        isEnablingThorchain = true
        defer { isEnablingThorchain = false }

        do {
            try await CoinService.addToChain(assets: [runeMeta], to: vault)
        } catch {
            logger.error("Failed to enable THORChain for LP: \(error.localizedDescription, privacy: .private)")
            return
        }

        if isThorchainEnabled {
            initialize()
        }
    }

    private func loadInitialState() {
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.fetchInboundAddressAndSetupApproval()
        }
        loadingTasks.append(task)
        loadPools()
    }

    private var amountInRaw: BigInt {
        SendCryptoLogic.amountInRaw(coin: coin, amount: amount.formatToDecimal(digits: coin.decimals))
    }

    private func fetchInboundAddressAndSetupApproval() async {
        let addresses = await ThorchainService.shared.fetchThorchainInboundAddress()

        if coin.chain == .thorChain {
            isApprovalRequired = false
            approvePayload = nil
            return
        }

        let chainName = ThorchainService.getInboundChainName(for: coin.chain)
        guard let inbound = addresses.first(where: { $0.chain.uppercased() == chainName.uppercased() }) else {
            return
        }

        if inbound.halted || inbound.global_trading_paused || inbound.chain_trading_paused || inbound.chain_lp_actions_paused {
            return
        }

        let destinationAddress: String
        if coin.shouldApprove {
            destinationAddress = inbound.router ?? inbound.address
        } else {
            destinationAddress = inbound.address
        }

        toAddress = destinationAddress
        isApprovalRequired = coin.shouldApprove
        if isApprovalRequired {
            approvePayload = toAddress.isEmpty ? nil : ERC20ApprovePayload(
                amount: amountInRaw,
                spender: toAddress
            )
        }
    }

    func loadPools() {
        isLoadingPools = true
        loadError = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadPoolsImpl()
        }
        loadingTasks.append(task)
    }

    private func loadPoolsImpl() async {
        do {
            let allPools = try await ThorchainService.shared.fetchLPPools()

            var poolOptions: [IdentifiableString] = []
            var nameMap: [String: String] = [:]
            var isInThePool: Bool = false

            if coin.chain == .thorChain {
                for pool in allPools {
                    let assetName = pool.asset
                    let cleanName = ThorchainService.cleanPoolName(assetName)
                    poolOptions.append(IdentifiableString(value: cleanName))
                    nameMap[cleanName] = assetName

                    if let lastPart = cleanName.uppercased().split(separator: ".").last,
                       coin.ticker.uppercased() == String(lastPart) {
                        isInThePool = true
                    }
                }
            } else {
                let currentSwap = coin.chain.swapAsset.uppercased()
                let filtered = allPools.filter { pool in
                    let components = pool.asset.split(separator: ".").map { String($0).uppercased() }
                    return components.count >= 2 && components[0] == currentSwap
                }
                for pool in filtered {
                    let assetName = pool.asset
                    let cleanName = ThorchainService.cleanPoolName(assetName)
                    poolOptions.append(IdentifiableString(value: cleanName))
                    nameMap[cleanName] = assetName

                    if let lastPart = cleanName.uppercased().split(separator: ".").last,
                       coin.ticker.uppercased() == String(lastPart) {
                        isInThePool = true
                    }
                }
            }

            // RUNE-pin when source coin is non-RUNE and not in the
            // selected pool — same intent as legacy initialize().
            if coin.ticker.uppercased() != "RUNE" && !isInThePool,
               let runeCoin = vault.runeCoin {
                coin = runeCoin
                coinSelectionHandler?(runeCoin)
            }

            self.poolNameMap = nameMap
            self.availablePools = poolOptions
            self.isLoadingPools = false
            self.loadError = nil

            if coin.chain != .thorChain && poolOptions.count == 1 {
                self.selectedPool = poolOptions[0]
            }
        } catch {
            self.availablePools = []
            self.isLoadingPools = false
            self.loadError = "failedToLoadPools".localized
        }
    }

    private func prefillPairedAddress() {
        if coin.chain == .thorChain {
            pairedAddress = ""
        } else if let thorCoin = vault.coins.first(where: { $0.chain == .thorChain && $0.isNativeToken }) {
            pairedAddress = thorCoin.address
        } else {
            pairedAddress = ""
        }
    }

    func prefillPairedAddressForPool(_ poolName: String) {
        let components = poolName.split(separator: ".").map { String($0).uppercased() }
        guard components.count >= 2 else {
            pairedAddress = ""
            pairedAssetBalance = ""
            return
        }

        let chainPrefix = components[0]
        let assetTicker = components[1]

        guard let chainCoin = vault.coins.first(where: {
            $0.isNativeToken && $0.chain.swapAsset.uppercased() == chainPrefix
        }) else {
            pairedAddress = ""
            pairedAssetBalance = ""
            return
        }

        pairedAddress = chainCoin.address

        if let assetCoin = vault.coins.first(where: { $0.chain == chainCoin.chain && $0.ticker.uppercased() == assetTicker }) {
            let balance = assetCoin.balanceDecimal.formatForDisplay()
            pairedAssetBalance = String(format: "balanceInParentheses".localized, balance, assetCoin.ticker.uppercased())
        } else if assetTicker == chainPrefix {
            let balance = chainCoin.balanceDecimal.formatForDisplay()
            pairedAssetBalance = String(format: "balanceInParentheses".localized, balance, chainCoin.ticker.uppercased())
        } else {
            pairedAssetBalance = "( \(assetTicker) not found in vault )"
        }
    }

    func updateSelectedPoolBalance(_ poolName: String) {
        if coin.chain == .thorChain {
            selectedPoolBalance = balance
            return
        }

        let components = poolName.split(separator: ".").map { String($0).uppercased() }
        guard components.count >= 2 else {
            selectedPoolBalance = balance
            return
        }

        let chainPrefix = components[0]
        let assetTicker = components[1]
        let chainCoins = vault.coins.filter { $0.chain.swapAsset.uppercased() == chainPrefix }

        if let native = chainCoins.first(where: { $0.isNativeToken && $0.ticker.uppercased() == assetTicker }) {
            selectedPoolBalance = formatBalance(native.balanceDecimal, ticker: native.ticker)
            return
        }
        if let token = chainCoins.first(where: { $0.ticker.uppercased() == assetTicker }) {
            selectedPoolBalance = formatBalance(token.balanceDecimal, ticker: token.ticker)
            return
        }
        selectedPoolBalance = "( \(assetTicker) not found in vault )"
    }

    func updateSelectedCoin(from poolName: String) {
        let components = poolName.split(separator: ".").map { String($0).uppercased() }
        guard components.count >= 2 else { return }
        let chainPrefix = components[0]
        let assetTicker = components[1]

        if let match = vault.coins.first(where: {
            $0.chain.swapAsset.uppercased() == chainPrefix &&
            $0.ticker.uppercased() == assetTicker
        }) {
            coin = match
            coinSelectionHandler?(match)
        }
    }

    private func formatBalance(_ balance: Decimal, ticker: String) -> String {
        String(format: "balanceInParentheses".localized, balance.formatForDisplay(), ticker.uppercased())
    }

    var isTheFormValid: Bool {
        guard isThorchainEnabled else { return false }
        let currentBalance = coin.balanceDecimal
        let amountValid = amount > 0 && amount <= currentBalance
        let poolValid = !selectedPool.value.isEmpty
        return amountValid && poolValid
    }

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
        guard isApprovalRequired, !toAddress.isEmpty else {
            return nil
        }
        return ERC20ApprovePayload(amount: amountInRaw, spender: toAddress)
    }

    var balance: String {
        let b = coin.balanceDecimal.formatForDisplay()
        return String(format: "balanceInParentheses".localized, b, coin.ticker.uppercased())
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        _ = isFastVault
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

// MARK: - Views

struct AddThorLPFormView: View {
    @Bindable var model: FunctionCallAddThorLP
    @Binding var selectedCoin: Coin

    var body: some View {
        Group {
            if model.isThorchainEnabled {
                formView
            } else {
                EnableThorchainCTASection(model: model)
            }
        }
        .withLoading(text: "enablingThorchain".localized, isLoading: $model.isEnablingThorchain)
        .onAppear {
            model.coinSelectionHandler = { coin in
                selectedCoin = coin
            }
            model.initialize()
        }
    }

    private var formView: some View {
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
                label: amountLabel,
                placeholder: "enterAmount".localized,
                value: $model.amount,
                isValid: .constant(true)
            )
        }
    }

    private var amountLabel: String {
        if model.coin.chain == .thorChain {
            return "\("amount".localized) \(model.balance)"
        }
        if !model.selectedPoolBalance.isEmpty {
            return "\("amount".localized) \(model.selectedPoolBalance)"
        }
        return "\("amount".localized) \(model.balance)"
    }
}

struct EnableThorchainCTASection: View {
    @Bindable var model: FunctionCallAddThorLP

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(Theme.fonts.bodyMRegular)
                    .foregroundStyle(Theme.colors.alertWarning)

                Text("thorChainNotEnabledForLP".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(title: "enableThorchain", isLoading: model.isEnablingThorchain) {
                Task { await model.enableThorchain() }
            }
        }
        .padding(16)
        .background(Theme.colors.bgSurface1)
        .cornerRadius(12)
    }
}

struct PoolSelectorSection: View {
    @Bindable var model: FunctionCallAddThorLP

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
            Text("loadingPools".localized)
                .font(Theme.fonts.bodyMRegular)
                .foregroundStyle(Theme.colors.textPrimary)

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
                    .foregroundStyle(.orange)

                Text(model.loadError ?? "noPoolsAvailable".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(2)

                Spacer()

                Button {
                    model.loadError = nil
                    model.isLoadingPools = true
                    model.loadPools()
                } label: {
                    Text("retry".localized)
                        .font(.caption)
                        .foregroundStyle(Theme.colors.primaryAccent1)
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
            selected: $model.selectedPool,
            mandatoryMessage: "*",
            descriptionProvider: { $0.value.isEmpty ? "selectPool".localized : $0.value },
            onSelect: { pool in
                model.selectedPool = pool

                if !pool.value.isEmpty {
                    if model.coin.chain == .thorChain {
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
            Text("erc20ApprovalRequired".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)

            Text("approvalRequiredMessageLP".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textPrimary)

            VStack(alignment: .leading, spacing: 4) {
                Text("approvalTransaction".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.primaryAccent1)
                Text("addLiquidityTransaction".localized)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.primaryAccent1)
            }
            .padding(.leading, 16)
        }
    }
}
