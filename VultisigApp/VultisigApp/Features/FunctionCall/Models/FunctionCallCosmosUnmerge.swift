//
//  FunctionCallCosmosUnmerge.swift
//  VultisigApp
//
//  RUJI UNMERGE sub-model. Form-VM rewrite per the FunctionCall
//  sub-model rewrite workstream — owns token selection, share amount,
//  available balance, and the derived contract address directly.
//  Cross-mutator: writes `selectedCoin` through a `@Binding<Coin>` so
//  the screen can refresh gas when the user picks a different merged
//  token. Async tasks are tracked in `loadingTasks` and cancelled on
//  deinit (no Combine cancellables under `@Observable`).
//

import BigInt
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.vultisig.app", category: "function-call-cosmos-unmerge")

@Observable
@MainActor
final class FunctionCallCosmosUnmerge {
    var amount: Decimal = 0.0
    var destinationAddress: String = ""

    var tokens: [IdentifiableString] = []
    var selectedToken: IdentifiableString

    var balanceLabel: String
    var sharePrice: Decimal = 0
    var totalShares: String = "0"
    var availableBalance: Decimal = 0.0
    var isLoading: Bool = false
    var customErrorMessage: String?

    @ObservationIgnored private let tokenPlaceholder: String
    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private let sourceTicker: String
    @ObservationIgnored private let sourceIsNative: Bool
    @ObservationIgnored private var loadingTasks: [Task<Void, Never>] = []

    init(coin: Coin, vault: Vault) {
        let placeholder = "theUnmerge".localized
        self.tokenPlaceholder = placeholder
        self.vault = vault
        self.sourceTicker = coin.ticker
        self.sourceIsNative = coin.isNativeToken
        self.selectedToken = .init(value: placeholder)
        self.balanceLabel = "sharesLabel".localized

        loadStaticMergeTokens()
        preSelectToken()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadOnChainMergeTokens()
        }
        loadingTasks.append(task)
    }

    deinit {
        loadingTasks.forEach { $0.cancel() }
    }

    private func loadStaticMergeTokens() {
        tokens = ThorchainMergeTokens.tokensToMerge.map { tokenInfo in
            IdentifiableString(value: tokenInfo.denom.uppercased())
        }
    }

    private func loadOnChainMergeTokens() async {
        let thorAddress = vault.coins.first(where: { $0.chain == .thorChain })?.address ?? ""
        guard !thorAddress.isEmpty else { return }

        do {
            let accounts = try await ThorchainService.shared.fetchAllRujiMergeBalances(thorAddr: thorAddress)
            let existing = Set(tokens.map { ThorchainService.normalizeRujiSymbol($0.value) })

            for account in accounts {
                let ticker = ThorchainService.normalizeRujiSymbol(account.symbol)
                guard !ticker.isEmpty, !existing.contains(ticker) else { continue }
                tokens.append(IdentifiableString(value: "THOR.\(ticker)"))
            }
        } catch {
            logger.error("Failed to fetch on-chain merge accounts: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func preSelectToken() {
        if !sourceIsNative,
           let match = ThorchainMergeTokens.tokensToMerge.first(where: {
               $0.denom.lowercased() == "thor.\(sourceTicker.lowercased())"
           }) {
            selectToken(.init(value: match.denom.uppercased()))
        } else if !tokens.isEmpty {
            selectToken(tokens[0])
        }
    }

    func selectToken(_ token: IdentifiableString) {
        selectedToken = token
        destinationAddress = ThorchainMergeTokens.tokensToMerge.first {
            $0.denom.lowercased() == token.value.lowercased()
        }?.wasmContractAddress ?? ""

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.fetchMergedBalance()
        }
        loadingTasks.append(task)
    }

    func selectedVaultCoin() -> Coin? {
        let ticker = selectedToken.value
            .lowercased()
            .replacingOccurrences(of: "thor.", with: "")
        return vault.coins.first { coin in
            coin.chain == .thorChain &&
            !coin.isNativeToken &&
            coin.ticker.lowercased() == ticker
        }
    }

    func fetchMergedBalance() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let thorAddress = vault.coins.first(where: { $0.chain == .thorChain })?.address ?? ""
            guard !thorAddress.isEmpty else {
                logger.error("No THORChain address found in vault")
                balanceLabel = "noThorAddressFound".localized
                amount = 0
                totalShares = "0"
                sharePrice = 0
                return
            }

            let rujiBalance = try await ThorchainService.shared.fetchRujiMergeBalance(
                thorAddr: thorAddress,
                tokenSymbol: selectedToken.value
            )

            totalShares = rujiBalance.shares
            sharePrice = rujiBalance.price

            if let sharesRaw = Decimal(string: rujiBalance.shares) {
                let divisor = NSDecimalNumber(decimal: pow(Decimal(10), 8))
                availableBalance = sharesRaw / divisor.decimalValue
            }

            amount = 0.0
            updateBalanceLabel()
        } catch {
            logger.error("Error fetching merged balance: \(error.localizedDescription, privacy: .public)")
            balanceLabel = "errorLoadingBalance".localized
            amount = 0
            availableBalance = 0
            totalShares = "0"
            sharePrice = 0
        }
    }

    private func updateBalanceLabel() {
        balanceLabel = String(format: "sharesBalance".localized, availableBalance.formatDecimalToLocale())
    }

    var isTokenSelected: Bool {
        selectedToken.value.lowercased() != tokenPlaceholder.lowercased()
    }

    var isAmountValid: Bool {
        amount > 0 && amount <= availableBalance
    }

    var isTheFormValid: Bool {
        let valid = isTokenSelected && isAmountValid && !amount.isZero
        if valid {
            customErrorMessage = nil
        } else if amount > 0 && amount > availableBalance {
            customErrorMessage = "insufficientBalanceForFunctions".localized
        }
        return valid
    }

    func validateAmount() {
        customErrorMessage = nil
        guard amount > 0 else {
            customErrorMessage = "enterValidAmount".localized
            return
        }
        guard amount <= availableBalance else {
            customErrorMessage = "insufficientBalanceForFunctions".localized
            return
        }
    }

    var description: String {
        toString()
    }

    func toString() -> String {
        let multiplier = NSDecimalNumber(decimal: pow(Decimal(10), 8))
        let rawShares = amount * multiplier.decimalValue
        let sharesStr = String(format: "%.0f", NSDecimalNumber(decimal: rawShares).doubleValue)
        return "unmerge:\(selectedToken.value.lowercased()):\(sharesStr)"
    }

    func toDictionary() -> ThreadSafeDictionary<String, String> {
        let dict = ThreadSafeDictionary<String, String>()
        dict.set("destinationAddress", destinationAddress)
        dict.set("selectedToken", selectedToken.value)
        dict.set("memo", toString())
        return dict
    }

    func toSendTransaction(
        coin: Coin,
        vault: Vault,
        gas: BigInt,
        isFastVault: Bool
    ) -> SendTransaction {
        SendTransaction.empty(coin: coin, vault: vault).copy(
            toAddress: destinationAddress,
            amount: amount.formatToDecimal(digits: coin.decimals),
            memo: toString(),
            gas: gas,
            transactionType: .thorUnmerge,
            memoFunctionDictionary: toDictionary().allItems()
        )
    }
}

struct CosmosUnmergeFormView: View {
    @Bindable var model: FunctionCallCosmosUnmerge
    @Binding var selectedCoin: Coin

    var body: some View {
        VStack(spacing: 16) {
            GenericSelectorDropDown(
                items: $model.tokens,
                selected: $model.selectedToken,
                mandatoryMessage: "*",
                descriptionProvider: { $0.value },
                onSelect: { asset in
                    model.amount = 0
                    model.availableBalance = 0
                    model.totalShares = "0"
                    model.sharePrice = 0
                    model.balanceLabel = "loading".localized
                    model.customErrorMessage = nil
                    model.selectToken(asset)
                }
            )

            if model.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    StyledFloatingPointField(
                        label: model.balanceLabel,
                        placeholder: "enterAmountToUnmerge".localized,
                        value: $model.amount,
                        isValid: .constant(true)
                    )
                    .onChange(of: model.amount) {
                        model.validateAmount()
                    }

                    if let errorMessage = model.customErrorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .onChange(of: model.selectedToken) {
            if let coin = model.selectedVaultCoin() {
                selectedCoin = coin
            }
        }
        .onAppear {
            if let coin = model.selectedVaultCoin() {
                selectedCoin = coin
            }
        }
    }
}
