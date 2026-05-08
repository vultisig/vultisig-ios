//
//  SwapDetailsViewModel.swift
//  VultisigApp
//
//  Form state owner for the swap-details screen. Holds every input + every
//  fetched derivative the user can affect (amount, coins, quote, fees,
//  discounts). When the user taps "Continue" and validation passes,
//  `makeTransaction()` materialises an immutable `SwapTransaction` that the
//  rest of the flow consumes.
//
//  Pure helpers in `SwapCryptoLogic` stay draft-shaped, so the VM exposes a
//  computed `draft: SwapDraft` snapshot built from its current fields. The
//  Interactor + formatters call sites keep working unchanged.
//

import BigInt
import OSLog
import SwiftUI

@MainActor
@Observable
final class SwapDetailsViewModel {
    @ObservationIgnored private let logger = Logger(subsystem: "com.vultisig.app", category: "swap-details")
    @ObservationIgnored private let interactor: SwapInteractor
    @ObservationIgnored private var updateQuoteTask: Task<Void, Never>?

    // MARK: - Form fields (mutable while the user is editing)

    var fromAmount: String = .empty
    var fromCoin: Coin = .example
    var toCoin: Coin = .example
    var fromCoins: [Coin] = []
    var toCoins: [Coin] = []

    var quote: SwapQuote?
    var thorchainFee: BigInt = .zero
    var gas: BigInt = .zero
    var vultDiscountBps: Int = 0
    var referralDiscountBps: Int = 0
    var isFastVault: Bool = false

    // MARK: - UI state (details-screen-only)

    var error: Error?
    var isLoading = false
    var isLoadingQuotes = false
    var isLoadingFees = false
    var isLoadingTransaction = false
    var dataLoaded = false
    var timer: Int = 59

    var fromChain: Chain?
    var toChain: Chain?
    var showFromChainSelector = false
    var showToChainSelector = false
    var showFromCoinSelector = false
    var showToCoinSelector = false
    var showAllPercentageButtons = true

    init(interactor: SwapInteractor = DefaultSwapInteractor.live) {
        self.interactor = interactor
    }

    // MARK: - Snapshot

    /// Snapshot of the current form state as a value type. Pure helpers
    /// (`SwapCryptoLogic.foo(draft:)`) and the Interactor consume this.
    var draft: SwapDraft {
        SwapDraft(
            fromAmount: fromAmount,
            thorchainFee: thorchainFee,
            gas: gas,
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps,
            quote: quote,
            isFastVault: isFastVault,
            fastVaultPassword: .empty,
            pendingRetryReason: nil,
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromCoins: fromCoins,
            toCoins: toCoins
        )
    }

    // MARK: - Loading

    func load(initialFromCoin: Coin?, initialToCoin: Coin?, vault: Vault) {
        guard !dataLoaded else { return }
        let allCoins = vault.coins
        guard !allCoins.isEmpty else { return }

        let (resolvedFromCoins, defaultFromCoin) = SwapCoinsResolver.resolveFromCoins(allCoins: allCoins)
        let resolvedFromCoin = initialFromCoin ?? defaultFromCoin

        let (resolvedToCoins, defaultToCoin) = SwapCoinsResolver.resolveToCoins(
            fromCoin: resolvedFromCoin,
            allCoins: allCoins,
            selectedToCoin: initialToCoin ?? .example
        )

        fromCoin = resolvedFromCoin
        toCoin = defaultToCoin
        fromCoins = resolvedFromCoins
        toCoins = resolvedToCoins
        dataLoaded = true
    }

    func loadFastVault(vault: Vault) async {
        isFastVault = await interactor.loadFastVault(vault: vault)
    }

    func updateCoinLists() {
        let (resolvedToCoins, resolvedToCoin) = SwapCoinsResolver.resolveToCoins(
            fromCoin: fromCoin,
            allCoins: fromCoins,
            selectedToCoin: toCoin
        )
        toCoin = resolvedToCoin
        toCoins = resolvedToCoins
    }

    // MARK: - User actions

    func switchCoins(vault: Vault, referredCode: String) {
        let oldFrom = fromCoin
        fromCoin = toCoin
        toCoin = oldFrom
        fetchQuotes(vault: vault, referredCode: referredCode)
    }

    func updateFromAmount(vault: Vault, referredCode: String) {
        fetchQuotes(vault: vault, referredCode: referredCode)
    }

    func updateFromCoin(coin: Coin, vault: Vault, referredCode: String) {
        fromCoin = coin
        fromChain = coin.chain
        fetchQuotes(vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
    }

    func updateToCoin(coin: Coin, vault: Vault, referredCode: String) {
        toCoin = coin
        toChain = coin.chain
        fetchQuotes(vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
    }

    func updateBalance(for coin: Coin) {
        Task {
            await interactor.updateBalance(for: coin)
        }
    }

    func updateTimer(vault: Vault, referredCode: String) {
        timer -= 1
        if timer < 1 {
            restartTimer(vault: vault, referredCode: referredCode)
        }
    }

    func restartTimer(vault: Vault, referredCode: String) {
        refreshData(vault: vault, referredCode: referredCode)
        timer = 59
    }

    func refreshData(vault: Vault, referredCode: String) {
        fetchQuotes(vault: vault, referredCode: referredCode)
    }

    // MARK: - Picker helpers

    func pickerFromCoinsForChain() -> [Coin] {
        SwapCryptoLogic.pickerFromCoins(draft: draft, fromChain: fromChain)
    }

    func pickerToCoinsForChain() -> [Coin] {
        SwapCryptoLogic.pickerToCoins(draft: draft, toChain: toChain)
    }

    func handleFromChainUpdate(vault: Vault) {
        guard
            let fromChain,
            fromChain != fromCoin.chain,
            let coin = SwapCryptoLogic.getDefaultCoin(for: fromChain, vault: vault)
        else { return }
        fromCoin = coin
    }

    func handleToChainUpdate(vault: Vault) {
        guard
            let toChain,
            toChain != toCoin.chain,
            let coin = SwapCryptoLogic.getDefaultCoin(for: toChain, vault: vault)
        else { return }
        toCoin = coin
    }

    // MARK: - Validation + transaction hand-off

    func validateForm() -> Bool {
        SwapCryptoLogic.validateForm(draft: draft, isLoading: isLoading)
    }

    /// Materialise an immutable `SwapTransaction` from the current form state.
    /// Returns nil if the form isn't valid (no quote, zero amount, balance
    /// insufficient, etc.) — caller can stay on the details screen.
    func makeTransaction() -> SwapTransaction? {
        guard validateForm(), let quote else { return nil }
        return SwapTransaction(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount.toDecimal(),
            quote: quote,
            gas: gas,
            thorchainFee: thorchainFee,
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps,
            isFastVault: isFastVault,
            feeCoin: SwapCryptoLogic.feeCoin(draft: draft)
        )
    }
}

// MARK: - Quote fetching

private extension SwapDetailsViewModel {

    func fetchQuotes(vault: Vault, referredCode: String) {
        updateQuoteTask?.cancel()

        guard !fromAmount.isEmpty else {
            quote = nil
            gas = .zero
            thorchainFee = .zero
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
                    await self?.updateQuotes(vault: vault, referredCode: referredCode)
                }
                group.addTask { [weak self] in
                    await self?.updateFees(vault: vault)
                }
            }
        }
    }

    func updateQuotes(vault: Vault, referredCode: String) async {
        quote = nil
        error = nil

        guard !fromAmount.isEmpty else { return }

        do {
            let result = try await interactor.fetchQuote(draft: draft, vault: vault, referredCode: referredCode)
            if let result {
                quote = result.quote
                vultDiscountBps = result.vultDiscountBps
                referralDiscountBps = result.referralDiscountBps
            }

            if let balanceError = SwapCryptoLogic.balanceError(draft: draft) {
                throw balanceError
            }
        } catch {
            guard (error as? URLError)?.code != .cancelled else { return }
            self.error = error
        }
    }

    func updateFees(vault: Vault) async {
        gas = .zero
        thorchainFee = .zero

        guard !fromAmount.isEmpty, !draft.fromAmount.toDecimal().isZero else { return }

        do {
            let chainSpecific = try await interactor.fetchChainSpecific(draft: draft)
            gas = chainSpecific.gas
            thorchainFee = try await interactor.computeThorchainFee(
                chainSpecific: chainSpecific,
                draft: draft,
                vault: vault
            )
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
