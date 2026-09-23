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
import Combine
import OSLog
import SwiftUI

@MainActor
@Observable
final class SwapDetailsViewModel {
    @ObservationIgnored private let logger = Log.swap.other
    @ObservationIgnored private let interactor: SwapInteractor
    @ObservationIgnored private let inputRate: (Coin, SettingsCurrency) -> Double?
    @ObservationIgnored private var rateSubscription: AnyCancellable?
    @ObservationIgnored private var updateQuoteTask: Task<Void, Never>?
    // Fee-only refresh kicked off by `selectProvider`. Kept separate from
    // `updateQuoteTask`, which `advancedSettingsSheetDidClose` reads as "a real
    // quote fetch is tracked" to decide whether to revalidate on close.
    @ObservationIgnored private var providerFeeTask: Task<Void, Never>?

    // Identity of the coin pair + amount the currently-held `quote` belongs to.
    // Stale-while-revalidate keeps a quote on screen only across a true silent
    // refresh (same pair AND same amount, i.e. the periodic auto-refresh). Any
    // pair OR amount change clears it so the "to" field falls back to the
    // instant indicative estimate and the summary shows its loading skeleton.
    @ObservationIgnored private var quotedPair: SwapPairIdentity?
    /// The PARSED amount the held quote was fetched for — the same value sent to
    /// the provider, so re-typing an equivalent amount is not a new swap.
    @ObservationIgnored private var quotedAmount: Decimal?
    @ObservationIgnored private var quotedSettings: SwapAdvancedSettings?
    /// A displayed quote may survive an outage; only a completed quote + fee
    /// refresh can authorize handoff. Dismissing the tooltip cannot change this.
    private var hasValidatedQuote = false

    // MARK: - Form fields (mutable while the user is editing)

    var fromAmount: String = .empty
    var fromCoin: Coin = .example {
        didSet {
            if oldValue.id != fromCoin.id { amountInput.reset() }
            refreshFromInputContext()
        }
    }
    private(set) var amountInput = SwapAmountInput()
    var toCoin: Coin = .example
    var fromCoins: [Coin] = []
    var toCoins: [Coin] = []

    /// Per-swap advanced settings (slippage / gas limit / external recipient).
    /// Reset to `.default` between swaps so a custom slippage never sticks.
    var advancedSettings: SwapAdvancedSettings = .default

    /// Snapshot of `advancedSettings` taken when the Advanced Settings sheet
    /// opens, so the sheet-close path can tell whether slippage / gas limit /
    /// external recipient changed and trigger a re-fetch only when one did.
    /// Route/provider selection (`selectedQuote`) is deliberately NOT part of
    /// this struct, so picking a route never triggers a re-fetch.
    @ObservationIgnored private var advancedSettingsSnapshot: SwapAdvancedSettings = .default

    /// Whether to show the Advanced Settings sheet.
    var showAdvancedSettingsSheet = false

    /// Gas-limit override applies only to EVM source chains. Excluded for a
    /// secured mint: its deposit is built by `ThorchainRouterDepositBuilder` from
    /// a synthesized send (not the swap path that honors the override), so
    /// offering it would silently drop the user's value.
    var isGasLimitSupported: Bool {
        fromCoin.chain.chainType == .EVM && !isSecuredMint
    }

    // MARK: - Quote state
    //
    // `bestQuote` is the auto-selected winner; `selectedQuote` is a manual
    // override (provider selection). The rest of the screen — fees, validation,
    // verify, sign — reads the computed `quote`, so a manual pick flows through
    // unchanged. A refresh re-resolves the pick by provider, and
    // `makeTransaction` hands that identity on so verify's refresh keeps it too.

    /// Full ranked candidate set (best→worst by net output). Drives the
    /// provider-selection sheet. Empty until the first quote of a pair lands.
    var allQuotes: [SwapQuote] = []
    /// Auto-selected winner for the current pair/amount.
    var bestQuote: SwapQuote?
    /// Manual provider override. Settings invalidation temporarily parks its
    /// identity for revalidation; dropping the choice posts a route notice.
    var selectedQuote: SwapQuote?
    /// Settings can invalidate payload bytes without changing the user's route.
    private var pendingSelectedProvider: (provider: SwapProvider, displayName: String?)?

    var selectedProviderDisplayName: String? {
        selectedQuote?.displayName ?? pendingSelectedProvider?.displayName
    }

    /// Set when a route pick was dropped; the screen renders and clears it.
    var routeSelectionNotice: String?

    /// Fit from each pair's last firm quote; survives the quote reset on edit so the next "~" estimate is fee-aware.
    private(set) var payoutFits: [SwapPairIdentity: SwapPayoutModel] = [:]

    /// The active quote the whole flow reads. A manual pick wins; otherwise the
    /// auto-selected best. Writing it replaces the slot wholesale and clears the
    /// override without a notice — no production path writes it; use
    /// `clearQuoteState`.
    var quote: SwapQuote? {
        get { selectedQuote ?? bestQuote }
        set {
            hasValidatedQuote = false
            pendingSelectedProvider = nil
            selectedQuote = nil
            bestQuote = newValue
            if newValue == nil {
                allQuotes = []
            }
        }
    }

    var thorchainFee: BigInt = .zero
    var gas: BigInt = .zero
    /// Oracle gas limit from chainSpecific (EVM only, zero elsewhere or until
    /// the fee data loads). Feeds the `EVMSwapFee` reconciliation together with
    /// `gas` (= maxFeePerGas for EVM) so the displayed fee is the signed bond.
    var gasLimit: BigInt = .zero
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

    /// The keyboard percentage-button toolbar shows only when no selector or
    /// sheet is covering the form — including the Advanced Settings sheet, so its
    /// own input fields don't sit under the percentage row.
    var showPercentageButtons: Bool {
        !showFromChainSelector
        && !showToChainSelector
        && !showFromCoinSelector
        && !showToCoinSelector
        && !showAdvancedSettingsSheet
    }

    init(
        interactor: SwapInteractor? = nil,
        inputRate: @escaping (Coin, SettingsCurrency) -> Double? = { coin, currency in
            RateProvider.shared.rate(for: coin, currency: currency)?.value
        }
    ) {
        // Resolved here rather than as a default argument, which is evaluated
        // outside the main actor that `DefaultSwapInteractor` is isolated to.
        self.interactor = interactor ?? DefaultSwapInteractor.live
        self.inputRate = inputRate
        rateSubscription = RateProvider.shared.ratesDidChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFromInputContext()
            }
        }
    }

    // MARK: - Amount input presentation

    var fromInputText: String { amountInput.isFiat ? amountInput.draft : fromAmount }
    var isFromInputFiat: Bool { amountInput.isFiat }
    var canToggleFromInputMode: Bool { amountInput.context != nil }
    var fromInputCurrencyCode: String { amountInput.context?.currency ?? SettingsCurrency.current.rawValue }

    /// Also called by the screen when the selected currency preference changes.
    /// Rate updates are display-only: canonical tokens and quotes stay unchanged.
    func refreshFromInputContext(currency: SettingsCurrency = .current) {
        let context = SwapAmountInput.Context(
            sourceID: fromCoin.id, currency: currency.rawValue,
            decimals: fromCoin.decimals, rate: inputRate(fromCoin, currency)
        )
        amountInput.refresh(context: context, tokenAmount: fromAmountDecimal)
    }

    func setFromInputEditing(_ editing: Bool) {
        amountInput.setEditing(editing, tokenAmount: fromAmountDecimal)
    }

    func toggleFromInputMode() {
        // Use exactly the context that rendered the tappable equivalent, rather
        // than a second live lookup that might have a different price.
        amountInput.toggle(tokenAmount: fromAmountDecimal)
    }

    /// The UI sends one draft edit here, without also invoking updateFromAmount.
    /// Paste detection uses draft length, never expanded converted-token length.
    func editFromInput(_ text: String, vault: Vault, immediate: Bool? = nil, renderedAsFiat: Bool? = nil) {
        let expectedFiat = renderedAsFiat ?? amountInput.isFiat
        let oldText = fromInputText
        refreshFromInputContext()
        // Compare the unit the field rendered, since a reset or toggle may have
        // happened before this callback arrived. Never reinterpret a stale edit
        // in the newly selected unit.
        guard expectedFiat == amountInput.isFiat else { return }
        if amountInput.isFiat {
            fromAmount = amountInput.editFiat(text)
        } else {
            fromAmount = text
            amountInput.synchronize(tokenAmount: fromAmountDecimal)
        }
        fetchQuotes(vault: vault, immediate: immediate ?? (abs(text.count - oldText.count) > 1))
    }

    // MARK: - Loading

    func load(initialFromCoin: Coin?, initialToCoin: Coin?, vault: Vault) {
        guard !dataLoaded else { return }
        let allCoins = vault.coins
        guard !allCoins.isEmpty else { return }

        // Resolve the default pair + lists off the chain-level provider
        // eligibility. THORChain / Maya are offered at the chain level, so this
        // is a pure synchronous resolve — no pool fetch, no re-resolve, no
        // placeholder flash. Token-level native-pool availability surfaces in
        // the picker via the native-pool `DestinationTokenProvider`s.
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

        // Every swap session starts at default advanced settings. The screen owns
        // a fresh VM per push so this is normally already `.default`, but resetting
        // here makes the session start explicit and guaranteed even if the VM is
        // reused. Guarded by `dataLoaded`, so it runs once per session, not on
        // every re-render.
        resetAdvancedSettings()
        dataLoaded = true
        prefetchSwapTokens()
    }

    /// Warm the per-chain swap token cache (`SwapTokenListCache`, via
    /// `TokenSearchService`) so the "Select asset" picker opens instantly instead
    /// of showing "Loading…". The picker opens to the from/to coin's chain, so
    /// prefetch both. Fire-and-forget; the cache coalesces an in-flight fetch if
    /// the user opens the picker mid-prefetch, and a fresh entry makes this a
    /// no-op.
    func prefetchSwapTokens() {
        let chains = Set([fromCoin.chain, toCoin.chain])
        for chain in chains {
            Task { _ = try? await TokenSearchService.shared.loadTokens(for: chain) }
        }
    }

    /// Resolve the VULT discount tier once on screen load, warming the session
    /// cache of Thorguard NFT ownership so the quote path doesn't re-run the
    /// eth_call on every fetch. Each quote still re-reads the VULT balance, so a
    /// balance arriving after this warm-up still reaches the fee discount.
    func warmDiscountTier(vault: Vault) {
        Task { [weak self] in
            guard let self else { return }
            await self.interactor.warmDiscountTier(for: vault)
        }
    }

    /// True when the user can open the provider-selection sheet: there's more
    /// than one quote to choose from. The Provider row only becomes tappable
    /// (chevron) when this holds. The advanced-settings entry point is already
    /// silver-gated, so no additional tier gate is applied here.
    var canSelectProvider: Bool {
        allQuotes.count > 1
    }

    /// Apply a manual provider pick. The new quote carries the previous
    /// selection's `gas`/`gasLimit`/`thorchainFee` until its own fees land, so
    /// `hasValidatedQuote` drops until that refresh completes — otherwise
    /// Continue could re-enable immediately with fees for the old route.
    func selectProvider(_ quote: SwapQuote, vault: Vault) {
        pendingSelectedProvider = nil
        selectedQuote = quote
        hasValidatedQuote = false
        if let quotedAmount {
            refitPayoutModel(fromAmount: quotedAmount, pair: currentPair, toCoin: toCoin)
        }
        providerFeeTask?.cancel()
        isLoadingFees = true
        providerFeeTask = Task { [weak self] in
            guard let self else { return }
            let feesSucceeded = await self.updateFees(vault: vault)
            guard !Task.isCancelled else { return }
            self.hasValidatedQuote = feesSucceeded && self.quoteMatchesCurrentRequest
            self.isLoadingFees = false
        }
    }

    enum RouteSelectionDropReason {
        case routeUnavailable
        case swapChanged

        var message: String {
            switch self {
            case .routeUnavailable:
                return "swapRouteUnavailableResetToAuto".localized
            case .swapChanged:
                return "swapRouteResetToAuto".localized
            }
        }
    }

    /// No-op without a pick, so a repeating invalidation (`fetchQuotes` runs on
    /// every keystroke) still surfaces at most one notice per pick.
    func dropRouteSelection(_ reason: RouteSelectionDropReason) {
        guard selectedQuote != nil || pendingSelectedProvider != nil else { return }
        selectedQuote = nil
        pendingSelectedProvider = nil
        routeSelectionNotice = reason.message
    }

    /// Quotes for the picker sheet, with the active (selected) quote pinned to
    /// the top; the rest keep their net-output ranking.
    var orderedPickerQuotes: [SwapQuote] {
        guard let active = quote, allQuotes.contains(active) else { return allQuotes }
        return [active] + allQuotes.filter { $0 != active }
    }

    /// Each provider row's reference output amount, prefixed with `~` (approximate).
    /// Uses the SAME `expectedNetToAmount(toCoin:)` the ranking sorts on, so the
    /// "Recommended" row always shows the largest amount in the list. Returns
    /// empty when the quote can't produce a comparable net amount.
    func referenceOutput(for candidate: SwapQuote) -> String {
        guard let amount = candidate.expectedNetToAmount(toCoin: toCoin) else { return .empty }
        return "~\(amount.formatForDisplay()) \(toCoin.ticker)"
    }

    /// Fiat equivalent of a row's reference output, using the same
    /// `expectedNetToAmount(toCoin:)`. Display-only; empty when not comparable.
    func referenceFiat(for candidate: SwapQuote) -> String {
        guard let amount = candidate.expectedNetToAmount(toCoin: toCoin) else { return .empty }
        return toCoin.fiat(decimal: amount).formatToFiat()
    }

    /// Provider/swap fee fiat for a route row (Select-route sub-sheet). Uses the
    /// per-quote provider fee — the EVM swap fee or the THORChain/Maya inbound
    /// fee — which is known for every candidate without the live network-gas
    /// estimate (that only exists for the active quote). Empty when not derivable.
    func routeFeeString(for candidate: SwapQuote) -> String {
        SwapCryptoLogic.swapFeeString(quote: candidate, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
    }

    /// Estimated time-to-completion for a route row, e.g. "~30s". Only
    /// THORChain/Maya quotes expose `totalSwapSeconds`; EVM aggregators don't,
    /// so this returns empty for them and the row renders the fee alone.
    func routeEtaString(for candidate: SwapQuote) -> String {
        guard let seconds = candidate.totalSwapSeconds else { return .empty }
        return String(format: "swapRouteEta".localized, seconds)
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

    // MARK: - Advanced settings sheet lifecycle

    /// Snapshot the settings that affect the quote/eligible-provider set when the
    /// Advanced Settings sheet opens, so the close path can detect a real change.
    func snapshotAdvancedSettings() {
        advancedSettingsSnapshot = advancedSettings
    }

    /// On sheet dismiss, re-fetch quotes only when a quote-affecting setting
    /// (slippage, gas limit, or external recipient) actually changed. These
    /// change the quote and/or the eligible-provider set: slippage and gas limit
    /// feed the quote request; the external recipient now changes provider
    /// eligibility (`providersHonoringRecipient`) and the built tx. Route/provider
    /// selection (`selectedQuote`) is not part of `advancedSettings`, so picking a
    /// route never reaches here — it only chooses among the quotes already fetched.
    /// No-op when nothing relevant changed (byte-identical to no interaction).
    func advancedSettingsSheetDidClose(vault: Vault) {
        let needsRevalidation = updateQuoteTask != nil && !hasValidatedQuote && fromAmountDecimal > 0
        guard advancedSettings != advancedSettingsSnapshot || needsRevalidation else { return }
        advancedSettingsSnapshot = advancedSettings
        fetchQuotes(vault: vault, immediate: true)
    }

    // MARK: - User actions

    func switchCoins(vault: Vault) {
        amountInput.reset()
        // Flipping the pair is a new swap — a custom slippage / gas limit /
        // external recipient must never leak across it. In particular the
        // recipient was validated for the OLD destination chain, which is now the
        // source, so carrying it over could misroute funds (Phase 5 reset
        // semantics).
        resetAdvancedSettings()
        let oldFrom = fromCoin
        fromCoin = toCoin
        toCoin = oldFrom
        // After the swap the destination list is stale relative to the new
        // source — re-resolve so `toCoins` matches the new `fromCoin` and
        // `toCoin` lands on a valid pair before the quote fetch runs.
        updateCoinLists()
        fetchQuotes(vault: vault)
        prefetchSwapTokens()
    }

    /// `immediate: true` skips the keystroke debounce — used for discrete actions
    /// (percentage buttons, paste) that set a final value in one shot. Free typing
    /// stays debounced.
    func updateFromAmount(vault: Vault, immediate: Bool = false) {
        amountInput.synchronize(tokenAmount: fromAmountDecimal)
        fetchQuotes(vault: vault, immediate: immediate)
    }

    func updateFromCoin(coin: Coin, vault: Vault) {
        // A new source pair starts fresh — a custom slippage / gas limit /
        // recipient must never stick across swaps (Phase 5 reset semantics).
        resetAdvancedSettings()
        fromCoin = coin
        fromChain = coin.chain
        // `toCoins` reflected the previous source's valid destinations —
        // recompute so `fetchQuotes` runs against the current valid pair.
        updateCoinLists()
        fetchQuotes(vault: vault)
        updateBalance(for: coin)
        prefetchSwapTokens()
    }

    func updateToCoin(coin: Coin, vault: Vault) {
        // A new destination invalidates a chain-specific external recipient and
        // resets the rest of the advanced settings (Phase 5 reset semantics).
        resetAdvancedSettings()
        toCoin = coin
        toChain = coin.chain
        fetchQuotes(vault: vault)
        updateBalance(for: coin)
        prefetchSwapTokens()
    }

    func updateBalance(for coin: Coin) {
        Task {
            await interactor.updateBalance(for: coin)
        }
    }

    /// A structural rejection clears the displayed quote but keeps retrying a
    /// previously quoted request, so a lifted halt can recover automatically.
    var showRefreshCounter: Bool {
        quote != nil || (fromAmountDecimal > 0 && quotedPair == currentPair && quotedAmount == fromAmountDecimal)
    }

    func updateTimer(vault: Vault) {
        guard showRefreshCounter else {
            timer = 59
            return
        }
        timer -= 1
        if timer < 1 {
            restartTimer(vault: vault)
        }
    }

    func restartTimer(vault: Vault) {
        refreshData(vault: vault)
        timer = 59
    }

    func refreshData(vault: Vault) {
        fetchQuotes(vault: vault)
    }

    func handleFromChainUpdate(vault: Vault) {
        guard
            let fromChain,
            fromChain != fromCoin.chain,
            let coin = SwapCryptoLogic.getDefaultCoin(for: fromChain, vault: vault)
        else { return }
        // A chain switch on its own does NOT reset the advanced settings: the
        // reset is token-driven. Assigning `fromCoin` here fires the screen's
        // `fromCoin` `onChange` → `updateFromCoin`, which performs the reset when
        // the selected token actually changes. A chain change that doesn't change
        // the token therefore leaves the settings intact (Phase 5 reset semantics).
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
        // A chain switch on its own does NOT reset the advanced settings — the
        // reset is token-driven. Assigning `toCoin` here fires the screen's
        // `toCoin` `onChange` → `updateToCoin`, which resets when the destination
        // token actually changes. A chain change that leaves the token unchanged
        // keeps the settings (Phase 5 reset semantics).
        toCoin = coin
    }

    // MARK: - Validation + transaction hand-off

    func validateForm() -> Bool {
        guard hasValidatedQuote, quoteMatchesCurrentRequest, error == nil,
              !isLoadingQuotes, !isLoadingFees, fromAmountDecimal > 0 else { return false }
        return SwapCryptoLogic.validateForm(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountDecimal,
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
            fromAmount: fromAmountDecimal,
            kind: .market(quote),
            mode: isSecuredMint ? .securedMint : .standard,
            gas: gas,
            gasLimit: gasLimit,
            thorchainFee: thorchainFee,
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps,
            feeCoin: feeCoin,
            advancedSettings: resolvedAdvancedSettings,
            selectedProvider: selectedQuote?.provider(fromChain: fromCoin.chain)
        )
    }

    /// The transaction Verify is handed, with its ERC-20 approval read once
    /// here: Verify shows that decision and signing uses it as is. Nil when the
    /// form isn't valid, or when the allowance could not be read, in which case
    /// `error` is set and Verify is not entered.
    func prepareTransaction(vault: Vault) async -> SwapTransaction? {
        guard !isLoadingTransaction, let transaction = makeTransaction() else { return nil }
        isLoadingTransaction = true
        defer { isLoadingTransaction = false }
        do {
            let decision = try await interactor.resolveApproval(for: transaction, vault: vault)
            return transaction.with(approvalDecision: decision)
        } catch {
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return nil }
            logger.warning("Approval read failed, not entering Verify: \(error.localizedDescription, privacy: .public)")
            self.error = error
            return nil
        }
    }

    /// Advanced settings as they apply to the current pair: an external recipient
    /// or gas-limit override only travels if it's valid for the destination/source
    /// chain. Slippage always carries.
    var resolvedAdvancedSettings: SwapAdvancedSettings {
        var resolved = advancedSettings
        if !isGasLimitSupported {
            resolved.gasLimit = nil
        }
        // A secured mint always deposits to the vault's own THORChain address, so
        // an external recipient must never travel — otherwise Verify would show a
        // recipient the SECURE+ memo (vault thor address) doesn't honor.
        if isSecuredMint {
            resolved.externalRecipient = nil
        }
        return resolved
    }

    /// Reset advanced settings to defaults. Called at session start (`load`) and
    /// whenever a swapped TOKEN changes (from/to coin pick, flip) so a custom
    /// slippage / gas limit / recipient never leaks across swaps. A chain switch
    /// resets only via the resulting token change, never on its own.
    func resetAdvancedSettings() {
        advancedSettings = .default
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
        SwapCryptoLogic.fee(quote: quote, fromCoin: fromCoin, thorchainFee: thorchainFee)
    }

    /// Network fee value shown on the details screen. For EVM aggregator/
    /// SwapKit routes this is the signed bond so it matches the verify screen,
    /// the co-signer, and the vault's signature. Also what the insufficient-gas
    /// gate (`balanceError`) validates against, since the bond is the node's
    /// real admission requirement.
    /// See `SwapCryptoLogic.displayedSwapNetworkFeeWei`.
    var displayedNetworkFeeWei: BigInt {
        SwapCryptoLogic.displayedSwapNetworkFeeWei(quote: quote, feeCoin: feeCoin, gas: gas, gasLimit: gasLimit, fee: fee)
    }

    var fromAmountDecimal: Decimal {
        SwapAmountInput.parseToken(fromAmount) ?? .zero
    }

    var amountInCoinDecimal: BigInt {
        let raw = fromCoin.raw(for: fromAmountDecimal)
        let balance = fromCoin.rawBalance.toBigInt()
        return balance > 0 ? min(raw, balance) : raw
    }

    var toAmountDecimal: Decimal {
        SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: toCoin)
    }

    /// Display-only indicative out-amount: this pair's last payout fit, else spot.
    /// Used to fill the "to" field instantly while the firm quote loads. Never
    /// read by validation or `makeTransaction()`.
    var toAmountIndicative: Decimal? {
        SwapCryptoLogic.toAmountIndicative(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmount: fromAmountDecimal,
            payoutModel: currentPayoutModel
        )
    }

    /// The string the "to" field renders. Firm value when a quote exists;
    /// otherwise the greyed `~`-prefixed indicative; otherwise empty.
    var toAmountDisplayString: String {
        if quote != nil {
            return toAmountDecimal.formatForDisplay()
        }
        if let indicative = toAmountIndicative {
            return "~\(indicative.formatForDisplay())"
        }
        return .empty
    }

    /// True while showing the indicative (not the firm) out-amount, so the view
    /// can grey it out. Display-only.
    var isShowingIndicativeAmount: Bool {
        quote == nil && toAmountIndicative != nil
    }

    /// Skeleton gate: the first-load skeleton shows only when a quote is being
    /// fetched AND there's no previous quote to keep on screen
    /// (stale-while-revalidate). Auto-refresh and edits with a prior quote keep
    /// the existing summary visible instead of blanking to a skeleton.
    var showsQuoteSkeleton: Bool {
        isLoadingQuotes && quote == nil
    }

    var router: String? {
        SwapCryptoLogic.router(quote: quote)
    }

    var isApproveRequired: Bool {
        SwapCryptoLogic.isApproveRequired(fromCoin: fromCoin, quote: quote)
    }

    /// Same-underlying secured selection (hold BTC → secured BTC): the flow mints
    /// via SECURE+ instead of a pool swap. Drives skipping the pool-quote fetch,
    /// the synthetic ~1:1 quote, and hiding the external-recipient / gas-limit
    /// advanced settings the mint builder doesn't honor.
    var isSecuredMint: Bool {
        SwapCryptoLogic.isSameUnderlyingSecuredMint(fromCoin: fromCoin, toCoin: toCoin)
    }

    var isDeposit: Bool {
        SwapCryptoLogic.isDeposit(fromCoin: fromCoin)
    }

    /// The sufficiency gate validates against the same fee the screen displays:
    /// the reconciled signed bond for EVM aggregator/SwapKit routes (an EVM
    /// node rejects any transaction whose account can't cover
    /// `gasLimit × maxFeePerGas + value`), the plain quote fee otherwise or
    /// until the oracle data loads.
    var balanceError: SwapCryptoLogic.Errors? {
        SwapCryptoLogic.balanceError(fromCoin: fromCoin, feeCoin: feeCoin, amount: fromAmountDecimal, fee: displayedNetworkFeeWei)
    }

    var fromFiatAmount: String {
        guard let context = amountInput.context else { return .empty }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .currency
        formatter.currencyCode = context.currency
        let value = fromAmountDecimal * context.rate
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? .empty
    }

    var toFiatAmount: String {
        SwapCryptoLogic.toFiatAmount(toCoin: toCoin, quote: quote)
    }

    /// Fiat sub-label for the "to" field. Mirrors the displayed crypto amount:
    /// firm quote's fiat when a quote exists, else the indicative amount's fiat
    /// so the sub-label doesn't read $0 next to a `~` estimate. Display-only.
    var toFiatAmountDisplay: String {
        if quote != nil {
            return toFiatAmount
        }
        guard let indicative = toAmountIndicative else { return toFiatAmount }
        return toCoin.fiat(decimal: indicative).formatForDisplay()
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

    /// Whether the itemized "Vultisig Fee" affiliate row should render (every
    /// market swap route, even at 0%; not secured mints or limit orders).
    var showAffiliateFeeRow: Bool {
        SwapCryptoLogic.showAffiliateFeeRow(quote: quote, mode: isSecuredMint ? .securedMint : .standard)
    }

    /// Whether the "Protocol Fee" (native outbound) row should render.
    var showProtocolFeeRow: Bool {
        SwapCryptoLogic.showProtocolFeeRow(quote: quote, toCoin: toCoin, mode: isSecuredMint ? .securedMint : .standard)
    }

    var swapFeeString: String {
        SwapCryptoLogic.swapFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin)
    }

    var swapGasString: String {
        SwapCryptoLogic.swapGasString(quote: quote, feeCoin: feeCoin, gas: gas, fee: displayedNetworkFeeWei)
    }

    var approveFeeString: String {
        SwapCryptoLogic.approveFeeString(feeCoin: feeCoin, fee: fee)
    }

    var isApproveFeeZero: Bool {
        SwapCryptoLogic.isApproveFeeZero(fee: fee)
    }

    var totalFeeString: String {
        SwapCryptoLogic.totalFeeString(quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin, fee: displayedNetworkFeeWei)
    }

    var feeLabelKeys: SwapCryptoLogic.FeeLabelKeys {
        SwapCryptoLogic.feeLabelKeys(feeChain: feeCoin.chain)
    }

    var durationString: String {
        SwapCryptoLogic.durationString(quote: quote)
    }

    var baseAffiliateFee: String {
        SwapCryptoLogic.baseAffiliateFee(
            quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin,
            fromAmount: fromAmountDecimal, vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
    }

    var swapFeeLabel: String {
        SwapCryptoLogic.swapFeeLabel(
            quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin,
            vultDiscountBps: vultDiscountBps
        )
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
            fromAmount: fromAmountDecimal, vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
    }

    var referralDiscount: String {
        SwapCryptoLogic.referralDiscount(
            quote: quote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: feeCoin,
            fromAmount: fromAmountDecimal, vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps
        )
    }

    var hasAppliedDiscounts: Bool {
        !vultDiscount.isEmpty || !referralDiscount.isEmpty
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

    // Single source of truth for the quote-fetch debounce. The amount field
    // reports keystrokes immediately, so all debounce timing lives here.
    static let quoteDebounce: Duration = .milliseconds(300)

    var currentPair: SwapPairIdentity {
        SwapPairIdentity(fromCoin: fromCoin, toCoin: toCoin)
    }

    /// Keyed by pair so flipping back to a pair keeps its fit.
    var currentPayoutModel: SwapPayoutModel? {
        payoutFits[currentPair]
    }

    /// Takes values captured before any await; a coin binding can change mid-fetch.
    /// A quote that cannot be fitted drops only this pair's entry.
    func refitPayoutModel(fromAmount: Decimal, pair: SwapPairIdentity, toCoin: Coin) {
        payoutFits[pair] = quote.flatMap { SwapPayoutModel.fit(quote: $0, fromAmount: fromAmount, toCoin: toCoin) }
    }

    /// Clear the full quote slot: the manual override, the best, and the ranked
    /// set. Keeps the three in lock-step so a stale provider list can't outlive
    /// the quote it belonged to.
    func clearQuoteState(reason: RouteSelectionDropReason = .swapChanged, preservingProvider: Bool = false) {
        hasValidatedQuote = false
        if preservingProvider {
            if let selectedQuote {
                pendingSelectedProvider = (selectedQuote.provider(fromChain: fromCoin.chain), selectedQuote.displayName)
            }
            selectedQuote = nil
        } else {
            dropRouteSelection(reason)
        }
        bestQuote = nil
        allQuotes = []
    }

    var quoteMatchesCurrentRequest: Bool {
        quotedPair == currentPair && quotedAmount == fromAmountDecimal && quotedSettings == advancedSettings
    }

    func fetchQuotes(vault: Vault, immediate: Bool = false) {
        updateQuoteTask?.cancel()
        providerFeeTask?.cancel()
        hasValidatedQuote = false

        // Empty or non-positive amount: drop any leftover quote/fee/discount
        // state from a prior valid input so `validateForm` doesn't pass on
        // a stale combination of new amount + old downstream values.
        if fromAmount.isEmpty || fromAmountDecimal.isZero {
            clearQuoteState()
            quotedPair = nil
            quotedAmount = nil
            quotedSettings = nil
            gas = .zero
            gasLimit = .zero
            thorchainFee = .zero
            vultDiscountBps = 0
            referralDiscountBps = 0
            error = nil
            isLoadingQuotes = false
            isLoadingFees = false
            return
        }

        // Stale-while-revalidate is for the silent periodic auto-refresh only:
        // keep the previous quote + summary on screen when pair, amount and
        // advanced settings are unchanged. Otherwise blank the quote so the
        // "to" field falls back to the instant indicative estimate and the
        // summary shows its loading skeleton (`showsQuoteSkeleton` =
        // isLoadingQuotes && quote == nil) until the fresh quote lands.
        let isSilentRefresh = quoteMatchesCurrentRequest
        if !isSilentRefresh {
            let samePairAndAmount = quotedPair == currentPair && quotedAmount == fromAmountDecimal
            clearQuoteState(preservingProvider: samePairAndAmount)
            if !samePairAndAmount {
                quotedPair = nil
                quotedAmount = nil
            }
            quotedSettings = nil
            gas = .zero
            gasLimit = .zero
            thorchainFee = .zero
            vultDiscountBps = 0
            referralDiscountBps = 0
        }
        error = nil
        isLoadingQuotes = true
        isLoadingFees = true

        updateQuoteTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: Self.quoteDebounce)
            }
            guard !Task.isCancelled, let self else { return }

            // Sequential, not parallel: `updateFees` reads `self.quote`, so
            // running them concurrently raced — fees could see the `quote = nil`
            // that `updateQuotes` writes before its fetch returns.
            //
            // Skip `updateFees` if `updateQuotes` already failed: with `quote`
            // still nil, `updateFees` would throw and overwrite the real error
            // (`swapAmountTooSmall`, `sameAsset`, etc.) with `insufficientGas`.
            //
            // Also skip when the balance is insufficient: the quote still renders
            // as a preview, but a fee you can't pay would surface the UTXO
            // `notEnoughUTXO` / `insufficientGas` fee errors. Insufficiency is
            // reflected only on the disabled Continue button, never as a fee error.
            let quoteSucceeded = await self.updateQuotes(vault: vault)
            var feesSucceeded = false
            if quoteSucceeded, !Task.isCancelled, self.balanceError == nil {
                feesSucceeded = await self.updateFees(vault: vault)
            }

            // Only the winning task clears the loading state. A superseded task
            // that resumed after being cancelled must leave the skeleton up for
            // its successor — otherwise clearing the flag unmasks the in-between
            // reset values and the previous quote flashes through.
            guard !Task.isCancelled else { return }
            self.hasValidatedQuote = quoteSucceeded && feesSucceeded && self.quoteMatchesCurrentRequest
            self.isLoadingQuotes = false
            self.isLoadingFees = false
        }
    }

    func updateQuotes(vault: Vault) async -> Bool {
        // Don't clear `quote` here: stale-while-revalidate keeps the previous
        // quote (and its summary) on screen until the fresh one lands. The pair
        // change in `fetchQuotes` already cleared it when it would be misleading.
        error = nil

        guard !fromAmount.isEmpty else { return false }

        // Parse once so the requested amount and the ownership stamp can't disagree.
        let requestedAmount = fromAmountDecimal
        let requestedPair = currentPair
        let requestedSettings = advancedSettings
        let requestedToCoin = toCoin

        // Same-underlying secured selection: there's no meaningful pool swap, so
        // skip the network quote and present a synthetic ~1:1 "Mint (SECURE+)"
        // quote. Confirm builds the real SECURE+ deposit payload.
        if isSecuredMint {
            // Candidate set collapses to the one synthetic mint quote.
            dropRouteSelection(.routeUnavailable)
            bestQuote = SwapCryptoLogic.securedMintQuote(fromAmount: requestedAmount, toCoin: toCoin)
            allQuotes = [bestQuote].compactMap { $0 }
            quotedPair = requestedPair
            quotedAmount = requestedAmount
            quotedSettings = requestedSettings
            refitPayoutModel(fromAmount: requestedAmount, pair: requestedPair, toCoin: requestedToCoin)
            vultDiscountBps = 0
            referralDiscountBps = 0
            return true
        }

        do {
            let result = try await interactor.fetchQuote(
                amount: requestedAmount,
                fromCoin: fromCoin,
                toCoin: toCoin,
                vault: vault,
                referredCode: vault.referredCode?.code ?? .empty,
                slippageBps: requestedSettings.slippage.bps,
                recipientAddress: requestedSettings.externalRecipient
            )
            // A superseding edit cancelled this fetch — don't write its stale
            // quote over the state the new fetch is about to populate.
            guard !Task.isCancelled else { return false }
            guard let result else { throw SwapError.routeUnavailable }
            // A coin picker assigns the coin one view update before the
            // screen's onChange cancels this fetch, so the pair can move on
            // while the quote is in flight. Keep that pair's fit; never
            // publish its quote under the new pair, where `validateForm`
            // would accept it and the signed memo would follow the old one.
            guard currentPair == requestedPair else {
                payoutFits[requestedPair] = SwapPayoutModel.fit(quote: result.quote, fromAmount: requestedAmount, toCoin: requestedToCoin)
                return false
            }
            guard fromAmountDecimal == requestedAmount, advancedSettings == requestedSettings else { return false }
            // Re-point at the object out of `result.allQuotes`, never the one
            // the user tapped: that is what keeps signing on current numbers.
            if let picked = selectedQuote?.provider(fromChain: fromCoin.chain) ?? pendingSelectedProvider?.provider {
                if let refreshed = result.allQuotes.first(where: { $0.provider(fromChain: fromCoin.chain) == picked }) {
                    selectedQuote = refreshed
                    pendingSelectedProvider = nil
                } else {
                    dropRouteSelection(.routeUnavailable)
                }
            }
            bestQuote = result.quote
            allQuotes = result.allQuotes
            quotedPair = requestedPair
            quotedAmount = requestedAmount
            quotedSettings = requestedSettings
            refitPayoutModel(fromAmount: requestedAmount, pair: requestedPair, toCoin: requestedToCoin)
            vultDiscountBps = result.vultDiscountBps
            referralDiscountBps = result.referralDiscountBps
            return true
        } catch {
            // Ignore cancellation from a superseding amount edit — surfacing it
            // would overwrite the next fetch's state with a stale error.
            guard !Task.isCancelled, currentPair == requestedPair,
                  fromAmountDecimal == requestedAmount, advancedSettings == requestedSettings else { return false }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return false
            }
            // Transport/provider outages may retain an estimate for display;
            // a structural rejection invalidates every candidate. Neither can sign.
            if error is SwapCryptoLogic.Errors || !SwapService.isTransientQuoteError(error) {
                clearQuoteState(reason: .routeUnavailable)
            }
            self.error = error
            return false
        }
    }

    func updateFees(vault: Vault) async -> Bool {
        // Don't zero `gas`/`thorchainFee` up front: during a same-pair refresh the
        // previous fee stays meaningful (stale-while-revalidate) and is replaced
        // on success below. A pair change already zeroed them in `fetchQuotes`.
        let amountDecimal = fromAmountDecimal
        guard !fromAmount.isEmpty, !amountDecimal.isZero else { return false }

        do {
            let chainSpecific = try await interactor.fetchChainSpecific(
                fromCoin: fromCoin,
                toCoin: toCoin,
                fromAmount: amountDecimal,
                quote: quote
            )
            guard !Task.isCancelled else { return false }
            let computedFee = try await interactor.computeThorchainFee(
                chainSpecific: chainSpecific,
                fromCoin: fromCoin,
                fromAmount: amountDecimal,
                vault: vault
            )
            // A superseding edit cancelled this fetch — don't write stale fees.
            guard !Task.isCancelled else { return false }
            gas = chainSpecific.gas
            gasLimit = chainSpecific.gasLimit ?? .zero
            thorchainFee = computedFee
            return true
        } catch {
            // A superseding amount edit cancels the in-flight task; cancellation
            // must not surface as a fee error — it was previously mapped to the
            // misleading `insufficientGas`, which is what users saw while typing.
            guard !Task.isCancelled else { return false }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return false
            }

            logger.warning("Update fees error: \(error.localizedDescription)")

            // Surface the real failure. Typed UTXO errors already flow through
            // unchanged; every other error (timeout, decode, TLS, node 5xx) was
            // previously relabeled as `insufficientGas` — a confident money
            // verdict the app cannot actually justify.
            self.error = error
            return false
        }
    }
}

// MARK: - Pair identity

/// Stable identity of a (from, to) coin pair, independent of the mutable `Coin`
/// reference. Used to decide whether a held quote still belongs to the current
/// pair so stale-while-revalidate never shows a quote from a different pair.
struct SwapPairIdentity: Hashable {
    let fromChain: Chain
    let fromTicker: String
    let fromContract: String
    let toChain: Chain
    let toTicker: String
    let toContract: String

    init(fromCoin: Coin, toCoin: Coin) {
        fromChain = fromCoin.chain
        fromTicker = fromCoin.ticker
        fromContract = fromCoin.contractAddress
        toChain = toCoin.chain
        toTicker = toCoin.ticker
        toContract = toCoin.contractAddress
    }
}
