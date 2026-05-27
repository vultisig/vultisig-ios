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
        // After the swap the destination list is stale relative to the new
        // source — re-resolve so `toCoins` matches the new `fromCoin` and
        // `toCoin` lands on a valid pair before the quote fetch runs.
        updateCoinLists()
        fetchQuotes(vault: vault, referredCode: referredCode)
    }

    func updateFromAmount(vault: Vault, referredCode: String) {
        fetchQuotes(vault: vault, referredCode: referredCode)
    }

    func updateFromCoin(coin: Coin, vault: Vault, referredCode: String) {
        fromCoin = coin
        fromChain = coin.chain
        // `toCoins` reflected the previous source's valid destinations —
        // recompute so `fetchQuotes` runs against the current valid pair.
        updateCoinLists()
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

    func handleFromChainUpdate(vault: Vault) {
        guard
            let fromChain,
            fromChain != fromCoin.chain,
            let coin = SwapCryptoLogic.getDefaultCoin(for: fromChain, vault: vault)
        else { return }
        fromCoin = coin
        // Source changed via chain switch — keep `toCoins` / `toCoin` consistent
        // so the destination picker doesn't show stale options.
        updateCoinLists()
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
        SwapCryptoLogic.validateForm(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmount,
            quote: quote,
            fee: fee,
            toAmount: toAmountDecimal,
            isSufficientBalance: balanceError == nil,
            isLoading: isLoading
        )
    }

    /// Materialise an immutable `SwapTransaction` from the current form state.
    /// Returns nil if the form isn't valid.
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
            feeCoin: feeCoin
        )
    }
}

// MARK: - Convenience computed helpers
//
// Sugar over the primitive-taking SwapCryptoLogic free functions. View code
// reads `vm.swapFeeString` instead of spelling out the args.

extension SwapDetailsViewModel {
    var feeCoin: Coin {
        SwapCryptoLogic.feeCoin(fromCoin: fromCoin, fromCoins: fromCoins)
    }

    var fee: BigInt {
        SwapCryptoLogic.fee(quote: quote, thorchainFee: thorchainFee)
    }

    var fromAmountDecimal: Decimal {
        SwapCryptoLogic.fromAmountDecimal(fromAmount: fromAmount)
    }

    var amountInCoinDecimal: BigInt {
        SwapCryptoLogic.amountInCoinDecimal(fromAmount: fromAmount, fromCoin: fromCoin)
    }

    var toAmountDecimal: Decimal {
        SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: toCoin)
    }

    var router: String? {
        SwapCryptoLogic.router(quote: quote)
    }

    var isApproveRequired: Bool {
        SwapCryptoLogic.isApproveRequired(fromCoin: fromCoin, quote: quote)
    }

    var isDeposit: Bool {
        SwapCryptoLogic.isDeposit(fromCoin: fromCoin)
    }

    var balanceError: SwapCryptoLogic.Errors? {
        SwapCryptoLogic.balanceError(fromCoin: fromCoin, feeCoin: feeCoin, fromAmount: fromAmount, fee: fee)
    }

    var fromFiatAmount: String {
        SwapCryptoLogic.fromFiatAmount(fromCoin: fromCoin, fromAmount: fromAmount)
    }

    var toFiatAmount: String {
        SwapCryptoLogic.toFiatAmount(toCoin: toCoin, quote: quote)
    }

    var showGas: Bool {
        SwapCryptoLogic.showGas(gas: gas)
    }

    var showFees: Bool {
        SwapCryptoLogic.showFees(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
    }

    var showTotalFees: Bool {
        SwapCryptoLogic.showTotalFees(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin, fee: fee)
    }

    var swapFeeString: String {
        SwapCryptoLogic.swapFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
    }

    var swapGasString: String {
        SwapCryptoLogic.swapGasString(quote: quote, feeCoin: feeCoin, gas: gas, fee: fee)
    }

    var approveFeeString: String {
        SwapCryptoLogic.approveFeeString(feeCoin: feeCoin, fee: fee)
    }

    var isApproveFeeZero: Bool {
        SwapCryptoLogic.isApproveFeeZero(fee: fee)
    }

    var totalFeeString: String {
        SwapCryptoLogic.totalFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin, fee: fee)
    }

    var durationString: String {
        SwapCryptoLogic.durationString(quote: quote)
    }

    var baseAffiliateFee: String {
        SwapCryptoLogic.baseAffiliateFee(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
    }

    var swapFeeLabel: String {
        SwapCryptoLogic.swapFeeLabel(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin, fromAmount: fromAmount)
    }

    var outboundFeeString: String {
        SwapCryptoLogic.outboundFeeString(quote: quote, toCoin: toCoin)
    }

    var vultDiscountLabel: String {
        SwapCryptoLogic.vultDiscountLabel(vultDiscountBps: vultDiscountBps)
    }

    var referralDiscountLabel: String {
        SwapCryptoLogic.referralDiscountLabel(referralDiscountBps: referralDiscountBps)
    }

    var vultDiscount: String {
        SwapCryptoLogic.vultDiscount(
            quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin,
            fromAmount: fromAmount, vultDiscountBps: vultDiscountBps
        )
    }

    var referralDiscount: String {
        SwapCryptoLogic.referralDiscount(
            quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin,
            fromAmount: fromAmount, vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
    }

    var priceImpactString: String {
        SwapCryptoLogic.priceImpactString(quote: quote)
    }

    var priceImpactColor: Color {
        SwapCryptoLogic.priceImpactColor(quote: quote)
    }
}

// MARK: - Quote fetching

private extension SwapDetailsViewModel {

    func fetchQuotes(vault: Vault, referredCode: String) {
        updateQuoteTask?.cancel()

        // Empty or non-positive amount: drop any leftover quote/fee/discount
        // state from a prior valid input so `validateForm` doesn't pass on
        // a stale combination of new amount + old downstream values.
        if fromAmount.isEmpty || fromAmount.toDecimal().isZero {
            quote = nil
            gas = .zero
            thorchainFee = .zero
            vultDiscountBps = 0
            referralDiscountBps = 0
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

            // Sequential, not parallel: `updateFees` reads `self.quote`, so
            // running them concurrently raced — fees could see the `quote = nil`
            // that `updateQuotes` writes before its fetch returns.
            //
            // Skip `updateFees` if `updateQuotes` already failed: with `quote`
            // still nil, `updateFees` would throw and overwrite the real error
            // (`swapAmountTooSmall`, `sameAsset`, etc.) with `insufficientGas`.
            await self?.updateQuotes(vault: vault, referredCode: referredCode)
            guard let self, self.error == nil, self.quote != nil else { return }
            await self.updateFees(vault: vault)
        }
    }

    func updateQuotes(vault: Vault, referredCode: String) async {
        quote = nil
        vultDiscountBps = 0
        referralDiscountBps = 0
        error = nil

        guard !fromAmount.isEmpty else { return }

        do {
            let result = try await interactor.fetchQuote(
                amount: fromAmount.toDecimal(),
                fromCoin: fromCoin,
                toCoin: toCoin,
                vault: vault,
                referredCode: referredCode
            )
            if let result {
                quote = result.quote
                vultDiscountBps = result.vultDiscountBps
                referralDiscountBps = result.referralDiscountBps
            }

            if let balanceError {
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

        let amountDecimal = fromAmount.toDecimal()
        guard !fromAmount.isEmpty, !amountDecimal.isZero else { return }

        do {
            let chainSpecific = try await interactor.fetchChainSpecific(
                fromCoin: fromCoin,
                toCoin: toCoin,
                fromAmount: amountDecimal,
                quote: quote
            )
            gas = chainSpecific.gas
            thorchainFee = try await interactor.computeThorchainFee(
                chainSpecific: chainSpecific,
                fromCoin: fromCoin,
                fromAmount: amountDecimal,
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
