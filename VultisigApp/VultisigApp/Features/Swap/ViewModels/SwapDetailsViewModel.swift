//
//  SwapDetailsViewModel.swift
//  VultisigApp
//

import SwiftUI
import OSLog

@MainActor
final class SwapDetailsViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-details")
    private var updateQuoteTask: Task<Void, Never>?

    @Published var error: Error?
    @Published var isLoading = false
    @Published var isLoadingQuotes = false
    @Published var isLoadingFees = false
    @Published var isLoadingTransaction = false
    @Published var dataLoaded = false
    @Published var timer: Int = 59

    @Published var fromChain: Chain?
    @Published var toChain: Chain?
    @Published var showFromChainSelector = false
    @Published var showToChainSelector = false
    @Published var showFromCoinSelector = false
    @Published var showToCoinSelector = false
    @Published var showAllPercentageButtons = true

    func load(initialFromCoin: Coin?, initialToCoin: Coin?, vault: Vault, tx: SwapTransaction) {
        guard !dataLoaded else { return }
        SwapCryptoLogic.load(initialFromCoin: initialFromCoin, initialToCoin: initialToCoin, vault: vault, tx: tx)
        dataLoaded = true
    }

    func loadFastVault(tx: SwapTransaction, vault: Vault) async {
        tx.isFastVault = await SwapCryptoLogic.loadFastVault(vault: vault)
    }

    func updateCoinLists(tx: SwapTransaction) {
        SwapCryptoLogic.updateCoinLists(tx: tx)
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

    func fetchQuotes(tx: SwapTransaction, vault: Vault, referredCode: String) {
        updateQuoteTask?.cancel()

        guard !tx.fromAmount.isEmpty else {
            tx.quote = nil
            tx.gas = .zero
            tx.thorchainFee = .zero
            error = nil
            isLoadingQuotes = false
            isLoadingFees = false
            return
        }

        updateQuoteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
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
        SwapCryptoLogic.pickerFromCoins(tx: tx, fromChain: fromChain)
    }

    func pickerToCoins(tx: SwapTransaction) -> [Coin] {
        SwapCryptoLogic.pickerToCoins(tx: tx, toChain: toChain)
    }

    func handleFromChainUpdate(tx: SwapTransaction, vault: Vault) {
        guard
            let fromChain,
            fromChain != tx.fromCoin.chain,
            let coin = SwapCryptoLogic.getDefaultCoin(for: fromChain, vault: vault)
        else { return }
        tx.fromCoin = coin
    }

    func handleToChainUpdate(tx: SwapTransaction, vault: Vault) {
        guard
            let toChain,
            toChain != tx.toCoin.chain,
            let coin = SwapCryptoLogic.getDefaultCoin(for: toChain, vault: vault)
        else { return }
        tx.toCoin = coin
    }
}

private extension SwapDetailsViewModel {
    func updateQuotes(tx: SwapTransaction, vault: Vault, referredCode: String) async {
        tx.quote = nil
        error = nil

        guard !tx.fromAmount.isEmpty else { return }

        do {
            let quote = try await SwapCryptoLogic.fetchQuote(tx: tx, vault: vault, referredCode: referredCode)
            tx.quote = quote

            if let balanceError = SwapCryptoLogic.balanceError(tx: tx) {
                throw balanceError
            }
        } catch {
            guard (error as? URLError)?.code != .cancelled else { return }
            self.error = error
        }
    }

    func updateFees(tx: SwapTransaction, vault: Vault) async {
        tx.gas = .zero
        tx.thorchainFee = .zero

        guard !tx.fromAmount.isEmpty, !tx.fromAmountDecimal.isZero else { return }

        do {
            let chainSpecific = try await SwapCryptoLogic.fetchChainSpecific(tx: tx)
            tx.gas = chainSpecific.gas
            tx.thorchainFee = try await SwapCryptoLogic.thorchainFee(for: chainSpecific, tx: tx, vault: vault)
        } catch {
            logger.warning("Update fees error: \(error.localizedDescription)")

            switch error {
            case KeysignPayloadFactory.Errors.notEnoughUTXOError,
                 KeysignPayloadFactory.Errors.utxoTooSmallError,
                 KeysignPayloadFactory.Errors.utxoSelectionFailedError:
                self.error = error
            default:
                self.error = SwapCryptoLogic.Errors.insufficientGas
            }
        }
    }
}
