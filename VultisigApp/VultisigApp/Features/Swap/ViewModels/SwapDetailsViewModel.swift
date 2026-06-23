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
    @ObservationIgnored private let eligibilityCache: NativePoolEligibilityCache
    @ObservationIgnored private var updateQuoteTask: Task<Void, Never>?

    // Identity of the coin pair + amount the currently-held `quote` belongs to.
    // Stale-while-revalidate keeps a quote on screen only across a true silent
    // refresh (same pair AND same amount, i.e. the periodic auto-refresh). Any
    // pair OR amount change clears it so the "to" field falls back to the
    // instant indicative estimate and the summary shows its loading skeleton.
    @ObservationIgnored private var quotedPair: SwapPairIdentity?
    @ObservationIgnored private var quotedAmount: String?

    // Live `Available` pool snapshots fetched on `load`, retained so the
    // recompute path (`updateCoinLists`) and the quote fetch resolve providers
    // off the SAME live-pool-augmented set the picker used — otherwise a token
    // made eligible by a live pool would be dropped at quote time and surface
    // `routeUnavailable`. `nil` (cold start / fetch failure) falls back to the
    // static eligibility, byte-identical to pre-dynamic behavior.
    @ObservationIgnored private var thorPools: [NativePoolAsset]?
    @ObservationIgnored private var mayaPools: [NativePoolAsset]?

    /// A pure per-coin provider lookup backed by the retained live-pool sets.
    @ObservationIgnored private var liveProviders: (Coin) -> [SwapProvider] {
        let thor = thorPools
        let maya = mayaPools
        return { $0.swapProviders(thorPools: thor, mayaPools: maya) }
    }

    // MARK: - Form fields (mutable while the user is editing)

    var fromAmount: String = .empty
    var fromCoin: Coin = .example
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

    /// Gas-limit override applies only to EVM source chains.
    var isGasLimitSupported: Bool {
        fromCoin.chain.chainType == .EVM
    }

    // MARK: - Quote state
    //
    // `bestQuote` is the auto-selected winner; `selectedQuote` is a manual
    // override (provider selection). The rest of the screen — fees, validation,
    // verify, sign — reads the computed `quote`, so a manual pick flows through
    // unchanged. A refresh resets `selectedQuote` so it re-defaults to Best.

    /// Full ranked candidate set (best→worst by net output). Drives the
    /// provider-selection sheet. Empty until the first quote of a pair lands.
    var allQuotes: [SwapQuote] = []
    /// Auto-selected winner for the current pair/amount.
    var bestQuote: SwapQuote?
    /// Manual provider override. `nil` means "use Best". Reset on every refresh.
    var selectedQuote: SwapQuote?

    /// The active quote the whole flow reads. A manual pick wins; otherwise the
    /// auto-selected best. Writing it (e.g. the reset paths, tests) clears the
    /// manual override and assigns the best slot so existing call sites behave
    /// exactly as before.
    var quote: SwapQuote? {
        get { selectedQuote ?? bestQuote }
        set {
            selectedQuote = nil
            bestQuote = newValue
            if newValue == nil {
                allQuotes = []
            }
        }
    }

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
        interactor: SwapInteractor = DefaultSwapInteractor.live,
        eligibilityCache: NativePoolEligibilityCache = .shared
    ) {
        self.interactor = interactor
        self.eligibilityCache = eligibilityCache
    }

    // MARK: - Loading

    func load(initialFromCoin: Coin?, initialToCoin: Coin?, vault: Vault) async {
        guard !dataLoaded else { return }
        let allCoins = vault.coins
        guard !allCoins.isEmpty else { return }

        // Resolve the default pair + lists SYNCHRONOUSLY off the static eligibility
        // first, so the screen shows the correct from/to coins immediately. The
        // live-pool fetch below is an `await` (an actor hop even when cached), so
        // resolving after it would flash the `.example` placeholder (BTC) in both
        // slots on every open. Static resolution is byte-identical to the
        // pre-dynamic default pair; the live pools only ADD tokens.
        applyResolvedCoins(
            allCoins: allCoins,
            initialFromCoin: initialFromCoin,
            initialToCoin: initialToCoin,
            providers: { $0.swapProviders }
        )
        // Every swap session starts at default advanced settings. The screen owns
        // a fresh VM per push so this is normally already `.default`, but resetting
        // here makes the session start explicit and guaranteed even if the VM is
        // reused. Guarded by `dataLoaded`, so it runs once per session, not on
        // every re-render.
        resetAdvancedSettings()
        dataLoaded = true
        prefetchSwapTokens()

        // Then fold in live `Available` pools (fetch-supersedes-by-UNION) so
        // previously-hidden tokens appear, and re-resolve the lists. Fail-open:
        // nil snapshots keep the static set. The current selection is preserved,
        // so a warm fetch only grows the lists — it never re-jumps the pair.
        thorPools = await eligibilityCache.pools(.thorchain)
        mayaPools = await eligibilityCache.pools(.mayachain)
        guard thorPools != nil || mayaPools != nil else { return }
        applyResolvedCoins(
            allCoins: allCoins,
            initialFromCoin: fromCoin,
            initialToCoin: toCoin,
            providers: liveProviders
        )
    }

    /// Resolve and assign the from/to coins + their picker lists for a given
    /// provider-eligibility closure. Shared by the synchronous static pass and
    /// the live-pool re-resolve so both produce identical end state.
    private func applyResolvedCoins(
        allCoins: [Coin],
        initialFromCoin: Coin?,
        initialToCoin: Coin?,
        providers: (Coin) -> [SwapProvider]
    ) {
        let (resolvedFromCoins, defaultFromCoin) = SwapCoinsResolver.resolveFromCoins(
            allCoins: allCoins,
            providers: providers
        )
        let resolvedFromCoin = initialFromCoin ?? defaultFromCoin

        let (resolvedToCoins, defaultToCoin) = SwapCoinsResolver.resolveToCoins(
            fromCoin: resolvedFromCoin,
            allCoins: allCoins,
            selectedToCoin: initialToCoin ?? .example,
            providers: providers
        )

        fromCoin = resolvedFromCoin
        toCoin = defaultToCoin
        fromCoins = resolvedFromCoins
        toCoins = resolvedToCoins
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

    /// Warm the per-session VULT discount-tier cache once on screen load so the
    /// quote path reads the cached tier (VULT balance + Thorguard NFT) instead of
    /// re-resolving it — and re-running the Thorguard eth_call — on every fetch.
    /// This feeds the VULT fee-discount applied on the quote path.
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

    /// Apply a manual provider pick.
    func selectProvider(_ quote: SwapQuote) {
        selectedQuote = quote
    }

    /// Whether `candidate` is the top-ranked (rate-best) quote — the one the list
    /// tags "Recommended". Defined as the first element of the net-output-sorted
    /// `allQuotes` so the tag always lands on the row showing the largest output.
    func isBest(_ candidate: SwapQuote) -> Bool {
        candidate == allQuotes.first
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
            selectedToCoin: toCoin,
            providers: liveProviders
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
    func advancedSettingsSheetDidClose(vault: Vault, referredCode: String) {
        guard advancedSettings != advancedSettingsSnapshot else { return }
        advancedSettingsSnapshot = advancedSettings
        fetchQuotes(vault: vault, referredCode: referredCode, immediate: true)
    }

    // MARK: - User actions

    func switchCoins(vault: Vault, referredCode: String) {
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
        fetchQuotes(vault: vault, referredCode: referredCode)
        prefetchSwapTokens()
    }

    /// `immediate: true` skips the keystroke debounce — used for discrete actions
    /// (percentage buttons, paste) that set a final value in one shot. Free typing
    /// stays debounced.
    func updateFromAmount(vault: Vault, referredCode: String, immediate: Bool = false) {
        fetchQuotes(vault: vault, referredCode: referredCode, immediate: immediate)
    }

    func updateFromCoin(coin: Coin, vault: Vault, referredCode: String) {
        // A new source pair starts fresh — a custom slippage / gas limit /
        // recipient must never stick across swaps (Phase 5 reset semantics).
        resetAdvancedSettings()
        fromCoin = coin
        fromChain = coin.chain
        // `toCoins` reflected the previous source's valid destinations —
        // recompute so `fetchQuotes` runs against the current valid pair.
        updateCoinLists()
        fetchQuotes(vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
        prefetchSwapTokens()
    }

    func updateToCoin(coin: Coin, vault: Vault, referredCode: String) {
        // A new destination invalidates a chain-specific external recipient and
        // resets the rest of the advanced settings (Phase 5 reset semantics).
        resetAdvancedSettings()
        toCoin = coin
        toChain = coin.chain
        fetchQuotes(vault: vault, referredCode: referredCode)
        updateBalance(for: coin)
        prefetchSwapTokens()
    }

    func updateBalance(for coin: Coin) {
        Task {
            await interactor.updateBalance(for: coin)
        }
    }

    /// The refresh countdown is meaningful only against a live quote. Until the
    /// user enters an amount and a valid quote comes back, there's nothing to
    /// refresh, so the counter stays hidden and parked.
    var showRefreshCounter: Bool {
        quote != nil
    }

    func updateTimer(vault: Vault, referredCode: String) {
        guard showRefreshCounter else {
            timer = 59
            return
        }
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
            feeCoin: feeCoin,
            advancedSettings: resolvedAdvancedSettings
        )
    }

    /// Advanced settings as they apply to the current pair: an external recipient
    /// or gas-limit override only travels if it's valid for the destination/source
    /// chain. Slippage always carries.
    var resolvedAdvancedSettings: SwapAdvancedSettings {
        var resolved = advancedSettings
        if !isGasLimitSupported {
            resolved.gasLimit = nil
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

    var fromAmountDecimal: Decimal {
        SwapCryptoLogic.fromAmountDecimal(fromAmount: fromAmount)
    }

    var amountInCoinDecimal: BigInt {
        SwapCryptoLogic.amountInCoinDecimal(fromAmount: fromAmount, fromCoin: fromCoin)
    }

    var toAmountDecimal: Decimal {
        SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: toCoin)
    }

    /// Display-only indicative out-amount from spot prices. Used to fill the "to"
    /// field instantly while the firm quote loads. Never read by validation or
    /// `makeTransaction()`.
    var toAmountIndicative: Decimal? {
        SwapCryptoLogic.toAmountIndicative(fromCoin: fromCoin, toCoin: toCoin, fromAmount: fromAmount)
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

    // Single source of truth for the quote-fetch debounce. The amount field
    // reports keystrokes immediately, so all debounce timing lives here.
    static let quoteDebounce: Duration = .milliseconds(300)

    var currentPair: SwapPairIdentity {
        SwapPairIdentity(fromCoin: fromCoin, toCoin: toCoin)
    }

    /// Clear the full quote slot: the manual override, the best, and the ranked
    /// set. Keeps the three in lock-step so a stale provider list can't outlive
    /// the quote it belonged to.
    func clearQuoteState() {
        selectedQuote = nil
        bestQuote = nil
        allQuotes = []
    }

    func fetchQuotes(vault: Vault, referredCode: String, immediate: Bool = false) {
        updateQuoteTask?.cancel()

        // Empty or non-positive amount: drop any leftover quote/fee/discount
        // state from a prior valid input so `validateForm` doesn't pass on
        // a stale combination of new amount + old downstream values.
        if fromAmount.isEmpty || fromAmount.toDecimal().isZero {
            clearQuoteState()
            quotedPair = nil
            quotedAmount = nil
            gas = .zero
            thorchainFee = .zero
            vultDiscountBps = 0
            referralDiscountBps = 0
            error = nil
            isLoadingQuotes = false
            isLoadingFees = false
            return
        }

        // Stale-while-revalidate is for the silent periodic auto-refresh only:
        // keep the previous quote + summary on screen when the pair AND amount
        // are unchanged. On any pair or amount change, blank the quote so the
        // "to" field falls back to the instant indicative estimate and the
        // summary shows its loading skeleton (`showsQuoteSkeleton` =
        // isLoadingQuotes && quote == nil) until the fresh quote lands.
        let isSilentRefresh = quotedPair == currentPair && quotedAmount == fromAmount
        if !isSilentRefresh {
            clearQuoteState()
            quotedPair = nil
            quotedAmount = nil
            gas = .zero
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
            await self.updateQuotes(vault: vault, referredCode: referredCode)
            if self.error == nil, self.quote != nil {
                await self.updateFees(vault: vault)
            }

            // Only the winning task clears the loading state. A superseded task
            // that resumed after being cancelled must leave the skeleton up for
            // its successor — otherwise clearing the flag unmasks the in-between
            // reset values and the previous quote flashes through.
            guard !Task.isCancelled else { return }
            self.isLoadingQuotes = false
            self.isLoadingFees = false
        }
    }

    func updateQuotes(vault: Vault, referredCode: String) async {
        // Don't clear `quote` here: stale-while-revalidate keeps the previous
        // quote (and its summary) on screen until the fresh one lands. The pair
        // change in `fetchQuotes` already cleared it when it would be misleading.
        error = nil

        guard !fromAmount.isEmpty else { return }

        do {
            let result = try await interactor.fetchQuote(
                amount: fromAmount.toDecimal(),
                fromCoin: fromCoin,
                toCoin: toCoin,
                vault: vault,
                referredCode: referredCode,
                thorPools: thorPools,
                mayaPools: mayaPools,
                slippageBps: advancedSettings.slippage.bps,
                recipientAddress: advancedSettings.externalRecipient
            )
            // A superseding edit cancelled this fetch — don't write its stale
            // quote over the state the new fetch is about to populate.
            guard !Task.isCancelled else { return }
            if let result {
                // Every refresh re-defaults to Best: drop any manual override so
                // the active `quote` tracks the fresh winner ("until next refresh"
                // persistence). `allQuotes` repopulates from the ranked set.
                selectedQuote = nil
                bestQuote = result.quote
                allQuotes = result.allQuotes
                quotedPair = currentPair
                quotedAmount = fromAmount
                vultDiscountBps = result.vultDiscountBps
                referralDiscountBps = result.referralDiscountBps
            }

            if let balanceError {
                throw balanceError
            }
        } catch {
            // Ignore cancellation from a superseding amount edit — surfacing it
            // would overwrite the next fetch's state with a stale error.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            self.error = error
        }
    }

    func updateFees(vault: Vault) async {
        // Don't zero `gas`/`thorchainFee` up front: during a same-pair refresh the
        // previous fee stays meaningful (stale-while-revalidate) and is replaced
        // on success below. A pair change already zeroed them in `fetchQuotes`.
        let amountDecimal = fromAmount.toDecimal()
        guard !fromAmount.isEmpty, !amountDecimal.isZero else { return }

        do {
            let chainSpecific = try await interactor.fetchChainSpecific(
                fromCoin: fromCoin,
                toCoin: toCoin,
                fromAmount: amountDecimal,
                quote: quote
            )
            guard !Task.isCancelled else { return }
            let computedFee = try await interactor.computeThorchainFee(
                chainSpecific: chainSpecific,
                fromCoin: fromCoin,
                fromAmount: amountDecimal,
                vault: vault
            )
            // A superseding edit cancelled this fetch — don't write stale fees.
            guard !Task.isCancelled else { return }
            gas = chainSpecific.gas
            thorchainFee = computedFee
        } catch {
            // A superseding amount edit cancels the in-flight task; cancellation
            // must not surface as a fee error — it was previously mapped to the
            // misleading `insufficientGas`, which is what users saw while typing.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }

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

// MARK: - Pair identity

/// Stable identity of a (from, to) coin pair, independent of the mutable `Coin`
/// reference. Used to decide whether a held quote still belongs to the current
/// pair so stale-while-revalidate never shows a quote from a different pair.
struct SwapPairIdentity: Equatable {
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
