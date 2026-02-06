//
//  SwapCryptoViewModel.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 02.04.2024.
//

import SwiftUI
import BigInt
import OSLog
import WalletCore
import Mediator

@MainActor
class SwapCryptoViewModel: ObservableObject, TransferViewModel {
    private let titles = ["swap", "swapOverview", "pair", "keysign", "done"]

    private var updateQuoteTask: Task<Void, Never>?
    private var updateFeesTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-crypto")

    // Logic delegation
    private let logic = SwapCryptoLogic()

    var keysignPayload: KeysignPayload?

    @Published var currentIndex = 1
    @Published var currentTitle = "swap"
    @Published var hash: String?
    @Published var approveHash: String?

    @Published var error: Error?
    @Published var isLoading = false
    @Published var isLoadingQuotes = false
    @Published var isLoadingFees = false
    @Published var isLoadingTransaction = false
    @Published var dataLoaded = false
    @Published var timer: Int = 59

    @Published var fromChain: Chain? = nil
    @Published var toChain: Chain? = nil
    @Published var showFromChainSelector = false
    @Published var showToChainSelector = false
    @Published var showFromCoinSelector = false
    @Published var showToCoinSelector = false
    @Published var showAllPercentageButtons = true

    var progress: Double {
        return Double(currentIndex) / Double(titles.count)
    }

    func load(initialFromCoin: Coin?, initialToCoin: Coin?, vault: Vault, tx: SwapTransaction) {
        guard !dataLoaded else { return }
        logic.load(initialFromCoin: initialFromCoin, initialToCoin: initialToCoin, vault: vault, tx: tx)
        dataLoaded = true
    }

    func loadFastVault(tx: SwapTransaction, vault: Vault) async {
        tx.isFastVault = await logic.loadFastVault(vault: vault)
    }

    func updateCoinLists(tx: SwapTransaction) {
        logic.updateCoinLists(tx: tx)
    }

    func progressLink(tx: SwapTransaction, hash: String) -> String? {
        return logic.progressLink(tx: tx, hash: hash)
    }

    func fromFiatAmount(tx: SwapTransaction) -> String {
        return logic.fromFiatAmount(tx: tx)
    }

    func toFiatAmount(tx: SwapTransaction) -> String {
        return logic.toFiatAmount(tx: tx)
    }

    func showGas(tx: SwapTransaction) -> Bool {
        return logic.showGas(tx: tx)
    }

    func showFees(tx: SwapTransaction) -> Bool {
        return logic.showFees(tx: tx)
    }

    func showTotalFees(tx: SwapTransaction) -> Bool {
        return logic.showTotalFees(tx: tx)
    }

    func showDuration(tx: SwapTransaction) -> Bool {
        return logic.showDuration(tx: tx)
    }

    func showAllowance(tx: SwapTransaction) -> Bool {
        return logic.showAllowance(tx: tx)
    }

    func showToAmount(tx: SwapTransaction) -> Bool {
        return logic.showToAmount(tx: tx)
    }

    func swapFeeString(tx: SwapTransaction) -> String {
        return logic.swapFeeString(tx: tx)
    }

    func swapGasString(tx: SwapTransaction) -> String {
        return logic.swapGasString(tx: tx)
    }

    func approveFeeString(tx: SwapTransaction) -> String {
        return logic.approveFeeString(tx: tx)
    }

    func isApproveFeeZero(tx: SwapTransaction) -> Bool {
        return logic.isApproveFeeZero(tx: tx)
    }


    func totalFeeString(tx: SwapTransaction) -> String {
        return logic.totalFeeString(tx: tx)
    }

    func isSufficientBalance(tx: SwapTransaction) -> Bool {
        return logic.isSufficientBalance(tx: tx)
    }

    func durationString(tx: SwapTransaction) -> String {
        return logic.durationString(tx: tx)
    }

    func baseAffiliateFee(tx: SwapTransaction) -> String {
        return logic.baseAffiliateFee(tx: tx)
    }

    func swapFeeLabel(tx: SwapTransaction) -> String {
        return logic.swapFeeLabel(tx: tx)
    }

    func vultDiscountLabel(tx: SwapTransaction) -> String {
        return logic.vultDiscountLabel(tx: tx)
    }

    func referralDiscountLabel(tx: SwapTransaction) -> String {
        return logic.referralDiscountLabel(tx: tx)
    }

    func vultDiscount(tx: SwapTransaction) -> String {
        return logic.vultDiscount(tx: tx)
    }

    func referralDiscount(tx: SwapTransaction) -> String {
        return logic.referralDiscount(tx: tx)
    }

    func priceImpactString(tx: SwapTransaction) -> String {
        return logic.priceImpactString(tx: tx)
    }

    func priceImpactColor(tx: SwapTransaction) -> Color {
        return logic.priceImpactColor(tx: tx)
    }

    func validateForm(tx: SwapTransaction) -> Bool {
        return logic.validateForm(tx: tx, isLoading: isLoading)
    }

    func moveToNextView() {
        currentIndex += 1
        currentTitle = titles[currentIndex-1]
    }

    func buildSwapKeysignPayload(tx: SwapTransaction, vault: Vault) async -> Bool {
        isLoadingTransaction = true
        defer { isLoadingTransaction = false }

        do {
            keysignPayload = try await logic.buildSwapKeysignPayload(tx: tx, vault: vault)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    func stopMediator() {
        Mediator.shared.stop()
    }

    func switchCoins(tx: SwapTransaction, vault: Vault, referredCode: String) {
        let fromCoin = tx.fromCoin
        let toCoin = tx.toCoin
        tx.fromCoin = toCoin
        tx.toCoin = fromCoin
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
    }

    func updateFromAmount(tx: SwapTransaction, vault: Vault, referredCode: String) {
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
    }

    func updateFromCoin(coin: Coin, tx: SwapTransaction, vault: Vault, referredCode: String) {
        tx.fromCoin = coin
        fromChain = coin.chain
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
    }

    func updateToCoin(coin: Coin, tx: SwapTransaction, vault: Vault, referredCode: String) {
        tx.toCoin = coin
        toChain = coin.chain
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
    }

    func updateBalance(for coin: Coin) {
        Task {
            await BalanceService.shared.updateBalance(for: coin)
        }
    }

    func handleBackTap() {
        currentIndex-=1
        currentTitle = titles[currentIndex-1]
    }

    func updateTimer(tx: SwapTransaction, vault: Vault, referredCode: String) {
        timer -= 1

        if timer < 1 {
            restartTimer(tx: tx, vault: vault, referredCode: referredCode)
        }
    }

    func restartTimer(tx: SwapTransaction, vault: Vault, referredCode: String) {
        refreshData(tx: tx, vault: vault, referredCode: referredCode)
        timer = 59
    }

    func refreshData(tx: SwapTransaction, vault: Vault, referredCode: String) {
        fetchQuotes(tx: tx, vault: vault, referredCode: referredCode)
    }

    func fetchFees(tx: SwapTransaction, vault: Vault) {
        updateFeesTask?.cancel()
        updateFeesTask = Task {[weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds delay
            guard !Task.isCancelled else { return }

            self?.isLoadingFees = true
            defer { self?.isLoadingFees = false }

            await self?.updateFees(tx: tx, vault: vault)
        }
    }

    func fetchQuotes(tx: SwapTransaction, vault: Vault, referredCode: String) {
        // this method is called when the user changes the amount, from/to coins, or chains
        // it will update the quotes after a short delay to avoid excessive requests
        updateQuoteTask?.cancel()

        // Don't show loading spinner if there's no amount to quote
        guard !tx.fromAmount.isEmpty else {
            tx.quote = nil       // Clear stale quote state
            tx.gas = .zero       // Clear stale gas fee
            tx.thorchainFee = .zero // Clear stale thorchain fee
            error = nil          // Clear any previous error
            isLoadingQuotes = false
            isLoadingFees = false
            return
        }

        updateQuoteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds delay
            guard !Task.isCancelled else { return }

            self?.isLoadingQuotes = true
            self?.isLoadingFees = true
            defer {
                self?.isLoadingQuotes = false
                self?.isLoadingFees = false
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    await self?.updateQuotes(tx: tx, vault: vault, referredCode: referredCode)
                }
                group.addTask { [weak self] in
                    await self?.updateFees(tx: tx, vault: vault)
                }
            }
        }
    }

    func pickerFromCoins(tx: SwapTransaction) -> [Coin] {
        return logic.pickerFromCoins(tx: tx, fromChain: fromChain)
    }

    func pickerToCoins(tx: SwapTransaction) -> [Coin] {
        return logic.pickerToCoins(tx: tx, toChain: toChain)
    }

    // Helper to get fee coin needed for view display
    func feeCoin(tx: SwapTransaction) -> Coin {
        return logic.feeCoin(tx: tx)
    }
}

private extension SwapCryptoViewModel {

    func updateQuotes(tx: SwapTransaction, vault: Vault, referredCode: String) async {
        // Loading state managed by caller

        tx.quote = nil

        error = nil

        guard !tx.fromAmount.isEmpty else { return }

        do {
            let quote = try await logic.fetchQuote(tx: tx, vault: vault, referredCode: referredCode)
            tx.quote = quote

            if !logic.isSufficientBalance(tx: tx) {
                throw SwapCryptoLogic.Errors.insufficientFunds
            }
        } catch {
            guard (error as? URLError)?.code != .cancelled else { return }
            self.error = error
        }
    }

    func updateFees(tx: SwapTransaction, vault: Vault) async {
        // Loading state managed by caller

        tx.gas = .zero
        tx.thorchainFee = .zero

        // Skip fee calculation if no amount is entered
        guard !tx.fromAmount.isEmpty, !tx.fromAmountDecimal.isZero else {
            return
        }

        do {
            let chainSpecific = try await logic.fetchChainSpecific(tx: tx)
            tx.gas = chainSpecific.gas
            tx.thorchainFee = try await logic.thorchainFee(for: chainSpecific, tx: tx, vault: vault)

        } catch {
            logger.warning("Update fees error: \(error.localizedDescription)")

            // Handle UTXO-specific errors for better user experience
            switch error {
            case KeysignPayloadFactory.Errors.notEnoughUTXOError,
                KeysignPayloadFactory.Errors.utxoTooSmallError,
                KeysignPayloadFactory.Errors.utxoSelectionFailedError:
                // These are UTXO-specific errors that should be shown directly
                self.error = error
            default:
                self.error = SwapCryptoLogic.Errors.insufficientFunds
            }
        }
    }
}

// MARK: - Asset Selection

extension SwapCryptoViewModel {
    func handleFromChainUpdate(tx: SwapTransaction, vault: Vault) {
        guard
            let fromChain,
            fromChain != tx.fromCoin.chain,
            let coin = logic.getDefaultCoin(for: fromChain, vault: vault)
        else { return }
        tx.fromCoin = coin
    }

    func handleToChainUpdate(tx: SwapTransaction, vault: Vault) {
        guard
            let toChain,
            toChain != tx.toCoin.chain,
            let coin = logic.getDefaultCoin(for: toChain, vault: vault) else { return }
        tx.toCoin = coin
    }
}
