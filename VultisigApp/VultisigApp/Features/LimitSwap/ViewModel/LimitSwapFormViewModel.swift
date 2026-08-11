//
//  LimitSwapFormViewModel.swift
//  VultisigApp
//

import BigInt
import Foundation
import Observation
import OSLog

private let logger = Log.swap.other

/// View-binding only. Holds the user-editable `LimitSwapDraft` plus derived UI
/// state (% from market, warning, loading). Service calls + composition live
/// in `LimitSwapInteractor`; this class owns no business logic.
///
/// **Market-price refresh cadence** (workstream design open question §5.3):
/// fetch-on-input only for Phase 1. The view invokes `refreshMarketPrice()`
/// when the user changes `fromAsset`, `toAsset`, or `sourceAmount`. Periodic
/// (e.g. 30s timer) refresh is deferred — revisit if QA surfaces stale-price
/// complaints.
@MainActor
@Observable
final class LimitSwapFormViewModel {

    var draft: LimitSwapDraft

    /// Current market price reference, used for % from market and preset pills.
    var marketPriceRef: Decimal?

    /// Set of chains currently routable through THORChain (intersection of
    /// our static prefix table and THORChain's live `inbound_addresses`,
    /// minus halted/paused chains, plus `.thorChain` since RUNE deposits
    /// don't go through an inbound vault). `nil` while loading; the picker
    /// shows everything (no filter) until populated. Refreshed via
    /// `refreshSupportedChains()`.
    var supportedChains: Set<Chain>?

    /// USD price per natural unit of the **target** asset. Synced from the
    /// owning view via `RateProvider`'s cached rate (`Coin.price`). Used by
    /// the price-display subtitle / $-mode primary; `0` means USD-unavailable
    /// and the display falls back to asset-only formatting.
    var targetUsdPricePerUnit: Decimal = 0

    /// USD price per natural unit of the **source** asset. Synced from the
    /// owning view via `RateProvider`'s cached rate (`Coin.price`). Used to
    /// size the pre-input market-price probe to a fixed fiat notional so a cheap
    /// source (e.g. RUNE) still gets a quote back (see `marketProbeAmount`); `0`
    /// means USD-unavailable and the probe falls back to a 1-unit quote.
    var sourceUsdPricePerUnit: Decimal = 0

    var isLoadingMarketPrice = false
    var marketPriceError: Error?

    /// Non-nil when the selected pair can't be placed as a resting `=<` order —
    /// an unsupported (unencodable) asset, or a pair THORChain refuses to quote
    /// (no pool / trading paused). Resolved by `refreshMarketPrice`: a poolless
    /// quote throws a `ThorchainSwapError` here. Drives the inline "can't route"
    /// row and blocks `canPlaceOrder`, so a poolless pair (e.g. RUNE→VULT,
    /// KUJI→ETH) can never reach Verify and rest as an unfillable order. `nil`
    /// while unresolved (the picker already filters chains) and after a
    /// successful probe. The coin picker filters by CHAIN routability only, so
    /// this per-PAIR/asset gate is what catches poolless pairs the picker admits.
    var pairUnroutableReason: LimitSwapPairUnroutableReason?

    /// Whether THORChain's Advanced Swap Queue (`EnableAdvSwapQueue` mimir) is
    /// live, so resting `=<` limit orders are actually accepted on-chain.
    /// `nil` while the gate hasn't been resolved yet. **Fail-closed:** placement
    /// is blocked until this is confirmed `true` (see `preparePlaceableOrder`);
    /// `nil`/`false` both block. Refreshed via `refreshAdvancedSwapQueueGate()`.
    var advancedSwapQueueEnabled: Bool?

    /// Convenience for the view: `true` only when the queue is confirmed live.
    var isAdvancedSwapQueueEnabled: Bool { advancedSwapQueueEnabled == true }

    /// Longest lifetime THORChain will honour for a resting order, in blocks —
    /// the `StreamingLimitSwapMaxAge` mimir, refreshed by `refreshMaxExpiry()`.
    ///
    /// Seeded with the documented default so the duration picker has a usable
    /// bound on first paint rather than a disabled or unbounded one, and so a
    /// failed fetch degrades to today's behaviour. Read from the mimir rather
    /// than hard-coded because the cap can be changed on-chain: if it is raised,
    /// the picker widens on its own.
    var maxExpiryBlocks: Int = THORChainConstants.defaultLimitSwapMaxAgeBlocks

    /// Whether `maxExpiryBlocks` reflects a COMPLETED fetch rather than the seed.
    ///
    /// The seed is a plausible value, not a resolved one — mainnet happens to run
    /// the default today, but a lower live cap would mean advertising (and
    /// signing) a window THORChain then silently shortens. Placement therefore
    /// waits for the fetch, exactly as it waits for the queue gate.
    ///
    /// This is a *resolution* flag, not a success flag: the fetch fails soft to
    /// the default, so this turns true either way. That keeps a network blip from
    /// blocking placement forever while still closing the pre-fetch window.
    private(set) var isMaxExpiryResolved = false

    /// Floor is the app's own, not the protocol's, and collapses to the ceiling
    /// if a mimir ever reports a cap below it — shared with the clamp and the
    /// validator so all three agree.
    var minExpiryBlocks: Int { effectiveMinExpiryBlocks(maxBlocks: maxExpiryBlocks) }

    /// Whether the current draft can be placed — gates the entry screen's Place
    /// Order button. Requires a positive amount + target price, the Advanced Swap
    /// Queue confirmed live, AND a RESOLVED network-fee estimate
    /// (`networkFeeEstimate > 0`). Gating on the resolved fee closes a
    /// fee-disclosure race: the estimate is dropped to `0` on every input change
    /// and re-fetched asynchronously, so without this the user could tap Place
    /// before it resolves and sign an order whose Verify / Done screens show a
    /// blank network-fee row — never seeing the real source-chain gas that is
    /// derived at sign time. While the fee recomputes the button stays disabled.
    ///
    /// `sourceCoin` is the vault coin the picker currently has selected — the
    /// same object the Sell row prints a balance for, so the gate can never
    /// judge a different balance from the one on screen. It is passed in rather
    /// than mirrored into a stored property precisely so there is no second copy
    /// to drift from `draft.fromAsset`.
    func canPlaceOrder(sourceCoin: Coin) -> Bool {
        draft.targetPrice > 0
            && draft.sourceAmount > 0
            // A positive deposit is not sufficient: `computeLim` truncates a
            // second time into 1e8 fixed point, so a dust amount at a low price
            // still floors the LIM to zero and throws at memo build. Requiring a
            // derivable output means the CTA can't enable for an order that can
            // only fail — reachable from either entry direction, and easier to
            // reach now that a deposit can be derived from a small stated output.
            && expectedBuyAmount > 0
            && isAdvancedSwapQueueEnabled
            // The TTL ceiling has to be a resolved value, not the seeded default:
            // a lower live cap would mean signing a window the chain shortens.
            // Resolution (not success) is the bar — the fetch fails soft.
            && isMaxExpiryResolved
            && networkFeeEstimate > 0
            // Affordability: the vault must hold the sell amount, and the fee on
            // top of it. Same rule as the market tab's Continue gate.
            && !balanceState(sourceCoin: sourceCoin).blocksPlacement
            // POSITIVE routability proof: a resolved market reference means the
            // market-price probe got a quote back, which proves the pair has a
            // THORChain pool (the picker only filters per-CHAIN, so a poolless
            // pair like RUNE→VULT / KUJI→ETH slips through). Requiring the
            // reference — rather than merely the ABSENCE of a known-bad verdict —
            // closes the pre-probe window where `pairUnroutableReason` hasn't
            // resolved yet, so a poolless pair can never reach Verify. `nil` while
            // the probe is pending or failed, and cleared to `nil` on pair change.
            && marketPriceRef != nil
            // Redundant with the positive proof above in every reachable state,
            // but kept as defence-in-depth: never place a pair the probe flagged.
            && pairUnroutableReason == nil
            // Prerequisites for building a placeable order — without these
            // `preparePlaceableOrder` can't assemble a memo, so disable the CTA
            // rather than let the tap silently no-op (per-ASSET routability that
            // the per-CHAIN picker filter doesn't cover).
            && draft.fromAsset.memoSymbol != nil
            && draft.toAsset.memoSymbol != nil
            && destinationAddress() != nil
    }

    /// Whether the vault can afford the current draft, judged against the SAME
    /// coin the Sell row prints a balance for.
    ///
    /// The arithmetic is `SwapCryptoLogic.balanceError` — the market swap's rule,
    /// reused rather than reimplemented, so an identical input can never produce
    /// two different verdicts across the two tabs. The fee coin is resolved with
    /// `SwapCryptoLogic.feeCoin`, the same helper `LimitSwapEntryView` uses to
    /// build the `SwapTransaction`: gas is paid in the source chain's NATIVE coin,
    /// so an ERC20 source's fee has to be read against ETH's 18 decimals and not
    /// the token's (reading wei against a token's decimals once produced a false
    /// `insufficientGas`).
    ///
    /// **The fee-in-flight window.** `networkFeeEstimate` is dropped to `0` on
    /// every input change and refetched after a debounce, so for a moment there
    /// is no fee to judge against. The two questions are split by what is
    /// knowable without one:
    ///
    /// - *Does the amount alone exceed the balance?* Fee-independent, so it is
    ///   answered immediately. The first call passes `fee: .zero`, which makes
    ///   `balanceError`'s gas arm unreachable by construction (the same-coin arm
    ///   needs `fromFee > 0`, the split-coin arm needs `fromFee > feeCoinBalance`)
    ///   — so a zero fee can only ever yield the funds verdict, never a gas one.
    /// - *Does the fee fit on top?* Not knowable, so it is not guessed at:
    ///   `.indeterminate` shows no row and keeps the CTA disabled. A gas error is
    ///   therefore never displayed and then withdrawn a frame later.
    func balanceState(sourceCoin: Coin) -> LimitSwapBalanceState {
        // The view can render one frame with a newly-picked coin and the previous
        // draft asset (the two are synced in an `onChange`). Comparing a BTC
        // amount against an ETH balance for that frame would flash a bogus row,
        // so refuse to judge until they agree. Fail-closed: `.indeterminate`
        // blocks placement.
        guard sourceCoin.chain == draft.fromAsset.chain,
              sourceCoin.ticker == draft.fromAsset.ticker,
              sourceCoin.contractAddress == draft.fromAsset.contractAddress else {
            return .indeterminate
        }

        let feeCoin = SwapCryptoLogic.feeCoin(fromCoin: sourceCoin, fromCoins: vault.coins)
        let amount = sourceCoin.decimal(for: draft.sourceAmount)

        // Fee-independent leg — a zero fee cannot reach the gas arm.
        if SwapCryptoLogic.balanceError(
            fromCoin: sourceCoin,
            feeCoin: feeCoin,
            amount: amount,
            fee: .zero
        ) != nil {
            return .insufficientFunds(sourceTicker: sourceCoin.ticker)
        }

        guard networkFeeEstimate > 0 else { return .indeterminate }

        switch SwapCryptoLogic.balanceError(
            fromCoin: sourceCoin,
            feeCoin: feeCoin,
            amount: amount,
            fee: networkFeeEstimate
        ) {
        case .none:
            return .sufficient
        case .some(.insufficientGas):
            return .insufficientGas(feeTicker: feeCoin.ticker)
        case .some:
            // The amount cleared the fee-free leg, so this can only be the
            // same-coin `amount + fee > balance` case that the gas arm didn't
            // claim. Report it as the funds problem the shared rule called it.
            return .insufficientFunds(sourceTicker: sourceCoin.ticker)
        }
    }

    /// User-facing error raised while assembling / pre-flighting the order in
    /// "Place Order" (memo byte-cap overflow, target-price overflow). Drives an
    /// alert in `LimitSwapEntryView`. `nil` clears the alert. Previously these
    /// failures were swallowed silently — the user tapped "Place Order" and
    /// nothing happened, with no feedback.
    var placeOrderError: LimitSwapPlaceOrderError?

    /// Estimated source-chain broadcast fee for the pending limit deposit, in the
    /// fee coin's smallest units. Refreshed by `refreshNetworkFeeEstimate` (on
    /// load / asset / amount change) and read at place time into the
    /// `SwapTransaction.networkFeeEstimate` so the shared Verify / Done screens can
    /// show and persist the limit order's network fee. `.zero` until the first
    /// estimate resolves. The limit "fee" is JUST the network fee — a resting
    /// `=<` order has no provider/inbound fee. NEVER feeds signing (the signer
    /// re-derives the fee from a fresh chain-specific fetch).
    var networkFeeEstimate: BigInt = .zero

    private let vault: Vault
    private let interactor: LimitSwapInteractor
    private let marketDataService: MarketDataServiceProtocol

    /// Tags each in-flight `refreshMarketPrice` so a slower older request
    /// can't overwrite a faster newer one's `marketPriceRef`/`error` after
    /// it lands. Pure UUID ordering — no pointer to the actual Task is
    /// kept, so cancellation is implicit (we just ignore the result).
    private var marketPriceRequestID = UUID()

    /// Tags each in-flight `refreshNetworkFeeEstimate` so a slower older request
    /// can't overwrite a faster newer one's `networkFeeEstimate`.
    private var networkFeeRequestID = UUID()

    /// Bumped on every MANUAL target-price edit. A debounced pair refresh captures
    /// this before its sleep and only re-seeds the Market preset if it hasn't
    /// changed — so a price the user typed while the fetch was pending isn't
    /// clobbered by the delayed auto-seed.
    private var targetPriceEditSeq = 0

    /// In-flight debounced PAIR refresh (market price + fee + preset re-seed).
    /// Cancelled and replaced so the two coin mutations a swap makes collapse
    /// into one round of fetches. Mirrors `SwapDetailsViewModel.fetchQuotes`.
    @ObservationIgnored private var pairRefreshTask: Task<Void, Never>?

    /// In-flight debounced AMOUNT fee refresh, separate from the pair task so a
    /// keystroke never cancels a pending pair refresh (and vice-versa).
    @ObservationIgnored private var feeRefreshTask: Task<Void, Never>?

    /// In-flight chart fetch. Its own handle so a range switch cancels only the
    /// chart, and an amount keystroke never cancels the chart at all — the
    /// series does not depend on the amount.
    @ObservationIgnored private var chartRefreshTask: Task<Void, Never>?

    /// Keystroke/selection debounce before the market-price / fee fetches fire.
    static let inputDebounce: Duration = .milliseconds(300)

    /// Pair-ratio history behind the price chart, or `nil` when one cannot be
    /// drawn — either side unpriced, the fetch failed, or the two histories
    /// could not be reconciled. The form then renders exactly as it did before
    /// the chart existed; placement is never gated on it.
    var pairChart: MarketChart?

    /// Window the chart plots. `1D` is deliberately absent from the picker: the
    /// drag zone has to span the preset pills' reach, roughly 15%, and a day's
    /// range is a fraction of that — the history renders as a flat ribbon under
    /// any domain policy, so the range would only ever disappoint.
    var chartRange: MarketChartRange = .month

    var isLoadingPairChart = false

    /// Whether the price chart is showing. Persisted, and **collapsed by
    /// default**: the chart is an optional way to set a price the form can
    /// already set numerically, so it opts in rather than claiming the vertical
    /// space of everyone who does not want it.
    ///
    /// `UserDefaults.bool` returns `false` for an unset key, so the default
    /// falls out of the storage rather than being restated here.
    var isChartExpanded: Bool {
        didSet { UserDefaults.standard.set(isChartExpanded, forKey: Self.chartExpandedKey) }
    }

    static let chartExpandedKey = "limitSwapChartExpanded"

    /// Invalidation token for the chart fetch, mirroring the market-price and
    /// fee refreshes: a range switch or pair change must not have an older
    /// in-flight series land on top of a newer one.
    @ObservationIgnored private var chartRequestID = UUID()

    init(
        initialDraft: LimitSwapDraft,
        vault: Vault,
        interactor: LimitSwapInteractor,
        marketDataService: MarketDataServiceProtocol = MarketDataService.shared
    ) {
        self.draft = initialDraft
        self.vault = vault
        self.interactor = interactor
        self.marketDataService = marketDataService
        self.isChartExpanded = UserDefaults.standard.bool(forKey: Self.chartExpandedKey)
    }

    // MARK: - User input mutations

    func amountChanged(_ amount: BigInt) {
        // Typing the Sell side makes it the stated one; Buy goes back to being
        // derived (`expectedBuyAmount` already reads from the signed-LIM path).
        draft.amountDriver = .sell
        draft.desiredTargetOutput = 0
        draft.sourceAmount = amount
        // The network fee (UTXO especially) is amount-dependent; drop the stale
        // estimate so a fee from a previous amount can never be snapshotted into
        // the placed order. A fresh estimate is re-fetched by the view.
        invalidateNetworkFeeEstimate()
        // The chart is deliberately NOT invalidated here. The series is keyed on
        // the pair, range and currency — never on the amount — and nothing in
        // this path re-triggers a fetch, so clearing it would blank the chart on
        // the first keystroke into the amount field and leave it blank until the
        // user switched range or swapped an asset.
    }

    /// Drop the pair chart and invalidate any in-flight fetch, SYNCHRONOUSLY.
    ///
    /// The series is priced in the OLD pair's units, so leaving it on screen
    /// during the debounce leaves a live price input that belongs to a pair the
    /// user is no longer trading. Dragging it then writes a value from the old
    /// pair's domain into the new pair's target price — BTC/ETH's ~30 becoming
    /// the target for BTC/USDC, whose real price is ~118,000 — and because a
    /// drag is a deliberate edit it also bumps the edit sequence, suppressing
    /// the auto-seed that would otherwise have corrected it. The order then
    /// places at that price and fills immediately, at a catastrophic loss.
    ///
    /// Deliberately different from a RANGE switch, which keeps the outgoing
    /// series on screen while the next one loads: there the units are unchanged,
    /// so a briefly stale line is only stale, and clearing it collapses the card.
    /// Here the units themselves are wrong, so there is nothing honest to show.
    private func invalidatePairChart() {
        chartRefreshTask?.cancel()
        chartRequestID = UUID()
        pairChart = nil
        isLoadingPairChart = false
    }

    /// Drop the cached network-fee estimate AND invalidate any in-flight
    /// `refreshNetworkFeeEstimate` — called whenever an input (source / target /
    /// amount) changes. Advancing the request ID is essential: without it an
    /// older estimate that was already awaiting can complete *after* the clear
    /// (when the next refresh hasn't advanced the token, e.g. the amount went to
    /// 0) and repopulate `networkFeeEstimate` with a stale value.
    private func invalidateNetworkFeeEstimate() {
        networkFeeEstimate = .zero
        networkFeeRequestID = UUID()
    }

    /// Formatted amount text for `pct`% of the source coin's balance, mirroring
    /// the market swap's percentage buttons — both go through
    /// `PercentageAmountLogic`, so the two flows share one precision rule.
    ///
    /// Phase-1 limit sources are native, and — matching the market
    /// (`show100 = !isNativeToken`) — native sources only expose 25/50/75, never
    /// a 100/Max button, so no gas headroom is reserved at input time; the
    /// deposit fee is applied later in the shared verify/keysign path.
    func sourceAmountText(forPercentage pct: Int, of coin: Coin) -> String {
        PercentageAmountLogic.amountText(
            percentage: pct,
            rawBalance: coin.rawBalance.toBigInt(),
            coinDecimals: coin.decimals
        )
    }

    func targetPriceChanged(_ price: Decimal) {
        draft.targetPrice = price
        // A manual edit: a pending pair refresh must not overwrite it with the
        // delayed Market preset.
        targetPriceEditSeq += 1
        reconcileAmountsAfterPriceChange()
    }

    /// Hold the amount the user stated and move the other one.
    ///
    /// Only the Buy-driven case needs work: when Sell is driving, the Buy display
    /// is `expectedBuyAmount`, already derived from the live price, so it follows
    /// on its own. When Buy is driving, the deposit is what has to change — the
    /// user asked for an output, and a different price means a different cost.
    ///
    /// Called from EVERY path that moves the price (the price field, the USD
    /// mirror, the percent field, the preset pills, a chart drag), because a rule
    /// that held for only some of them would be worse than no rule: the figure
    /// the user typed would survive one interaction and silently drift on another.
    private func reconcileAmountsAfterPriceChange() {
        guard draft.amountDriver == .buy, draft.desiredTargetOutput > 0 else { return }
        setDerivedSourceAmount(limitSourceAmount(
            forTargetOutput: draft.desiredTargetOutput,
            targetPrice: draft.targetPrice,
            sourceDecimals: draft.fromAsset.decimals
        ))
    }

    /// Write a DERIVED deposit, invalidating the fee estimate only if it actually
    /// moved.
    ///
    /// The fee refresh is driven by an observer on `draft.sourceAmount`, so an
    /// unconditional invalidation is a deadlock when truncation leaves the
    /// deposit unchanged: the estimate is zeroed, nothing observes a change, no
    /// replacement is scheduled, and `canPlaceOrder` — which requires a resolved
    /// fee — stays false indefinitely. Small price nudges under a Buy-driven
    /// entry hit this readily, since the derived deposit often lands on the same
    /// smallest unit.
    private func setDerivedSourceAmount(_ amount: BigInt) {
        guard amount != draft.sourceAmount else { return }
        draft.sourceAmount = amount
        invalidateNetworkFeeEstimate()
    }

    /// Set the output the user wants to receive, deriving the deposit that buys it.
    ///
    /// The stated output is retained (`desiredTargetOutput`) rather than being
    /// re-read from the display later: the displayed buy is itself derived from
    /// the current price, so recomputing from it on each price change would walk
    /// the typed figure away from what was asked for.
    ///
    /// The Buy field then settles to `expectedBuyAmount` — re-derived from the
    /// truncated deposit through the same path the signed memo's LIM uses — so a
    /// typed `10` may read back as `9.99999998`. That is the order's real
    /// guaranteed minimum, and it keeps display == memo.
    func buyAmountChanged(_ output: Decimal) {
        draft.amountDriver = .buy
        draft.desiredTargetOutput = output
        setDerivedSourceAmount(limitSourceAmount(
            forTargetOutput: output,
            targetPrice: draft.targetPrice,
            sourceDecimals: draft.fromAsset.decimals
        ))
    }

    /// Set the target price from a typed **percent offset against market** — the
    /// exact inverse of `pctFromMarket`, and the same arithmetic the preset pills
    /// run, so the field and the pills can never disagree.
    ///
    /// No-op without a market reference: an offset has nothing to offset from,
    /// and the field is disabled in that state anyway. Rounded to 8 decimals like
    /// every other price-setting path so the stored price never carries more
    /// precision than the signed memo's LIM can express.
    ///
    /// Routed through `targetPriceChanged`, so a typed offset counts as the
    /// deliberate price choice it is and a pending pair refresh's delayed Market
    /// auto-seed cannot clobber it.
    func pctFromMarketChanged(_ pct: Decimal) {
        guard let price = targetPrice(forPctFromMarket: pct) else { return }
        targetPriceChanged(price)
    }

    /// The canonical target price a given percent offset maps to, or `nil` when
    /// there is no market reference to offset from.
    ///
    /// Exposed (rather than inlined into `pctFromMarketChanged`) because the view
    /// needs the SAME mapping to answer a different question: *does the offset
    /// field's current text still describe the price we hold?* If it does, the
    /// field is left alone — which preserves a typed `7.555` instead of rounding
    /// it to the two-decimal display form, and keeps the caret still mid-edit. If
    /// it doesn't, the price moved for some other reason (a chart drag, a preset,
    /// a fresh market quote) and the field has to follow it. Two copies of this
    /// arithmetic would let those two answers drift apart.
    func targetPrice(forPctFromMarket pct: Decimal) -> Decimal? {
        guard let market = marketPriceRef else { return nil }
        var raw = computePresetPrice(marketPrice: market, pctAboveMarket: pct)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 8, .plain)
        return rounded
    }

    /// Set the target price from a USD-denominated edit of the price display.
    /// `draft.targetPrice` is ALWAYS stored in target-asset terms (the LIM source
    /// the signed memo is derived from), so the USD value is converted back via
    /// the target's USD rate — the exact inverse of the display's
    /// `targetPrice × targetUsdPricePerUnit`. NEVER stores the USD number as the
    /// target price. No-op when the rate is unavailable (USD editing is disabled).
    ///
    /// The result is rounded to 8 decimals (the memo LIM's 1e8 fixed-point
    /// precision, matching `selectPresetPct`) so the stored price never carries
    /// more precision than the signed order can, and the asset-text mirror
    /// (`priceText`, capped at 8 dp) round-trips it exactly instead of rounding
    /// it back through its own sync.
    func targetPriceChangedFromUsd(_ usd: Decimal) {
        guard targetUsdPricePerUnit > 0 else { return }
        var raw = usd / targetUsdPricePerUnit
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 8, .plain)
        targetPriceChanged(rounded)
    }

    /// Set the target price from a preset pill (`Market`/`+1%`/`+5%`/`+10%`).
    /// No-op if `marketPriceRef` is unset (preset is meaningless without a base).
    /// Result is rounded to 8 decimals so the price text↔draft round-trip is
    /// stable (the formatter caps at 8; without rounding, parse(format(x)) != x
    /// for high-precision quotes).
    /// `userInitiated` is `true` for a preset PILL tap (a deliberate price
    /// selection that must not be overwritten by a pending auto-seed) and `false`
    /// for the programmatic Market auto-seed (on load / pair change).
    func selectPresetPct(_ pct: Int, userInitiated: Bool = true) {
        guard let market = marketPriceRef else { return }
        let raw = computePresetPrice(marketPrice: market, pctAboveMarket: Decimal(pct))
        var rounded = Decimal()
        var input = raw
        NSDecimalRound(&rounded, &input, 8, .plain)
        draft.targetPrice = rounded
        if userInitiated {
            // A user's preset selection is a price choice — a pending pair
            // refresh's delayed Market auto-seed must not clobber it.
            targetPriceEditSeq += 1
        }
        // Assigns the price directly rather than going through
        // `targetPriceChanged`, so the driver rule has to be applied here too.
        reconcileAmountsAfterPriceChange()
    }

    /// Set the target price from a drag on the chart.
    ///
    /// The chart plots in `Double` while the order is priced in `Decimal`, and
    /// `Decimal(someDouble)` carries the full binary expansion — 31.8255 arrives
    /// as 31.825500000000000682. Rounded to 8 decimals, the memo LIM's
    /// fixed-point precision, exactly as the preset and USD paths do, so a
    /// dragged price can never be stored with more precision than the signed
    /// order can express and the price-text round-trip stays stable.
    ///
    /// Routed through `targetPriceChanged` rather than assigning the draft
    /// directly: a drag is a deliberate price choice, so it has to bump the edit
    /// sequence too, or a pending pair refresh would land and overwrite it with
    /// the Market preset a moment after the finger lifts.
    func targetPriceChangedFromChart(_ price: Double) {
        guard price.isFinite, price > 0 else { return }
        var raw = Decimal(price)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 8, .plain)
        guard rounded > 0 else { return }
        targetPriceChanged(rounded)
    }

    func selectChartRange(_ range: MarketChartRange, currency: SettingsCurrency) {
        guard range != chartRange else { return }
        chartRange = range
        chartRefreshTask?.cancel()
        chartRefreshTask = Task { [weak self] in
            await self?.refreshPairChart(currency: currency)
        }
    }

    /// Load the pair-ratio series for the current assets and range.
    ///
    /// The previous series is deliberately left on screen while a new one loads:
    /// clearing it first collapses the card's height and the whole form jumps,
    /// which on a range switch is a worse experience than a briefly stale line.
    /// Show or hide the chart, persisting the choice.
    ///
    /// Expanding is what triggers the first fetch — while collapsed nothing is
    /// requested at all, so a user who never opens it costs no market-data
    /// traffic. The loading flag is raised synchronously so the content does not
    /// render one frame of "unavailable" before the request has started.
    func setChartExpanded(_ expanded: Bool, currency: SettingsCurrency) {
        isChartExpanded = expanded
        guard expanded, pairChart == nil else { return }
        isLoadingPairChart = true
        chartRefreshTask?.cancel()
        chartRefreshTask = Task { [weak self] in
            await self?.refreshPairChart(currency: currency)
        }
    }

    func refreshPairChart(currency: SettingsCurrency) async {
        // Collapsed means nobody is looking, so the two requests this would make
        // are pure waste — on open and again on every pair change. The chart is
        // fetched when it is first expanded instead.
        guard isChartExpanded else {
            isLoadingPairChart = false
            return
        }
        let requestID = UUID()
        chartRequestID = requestID
        isLoadingPairChart = true
        defer {
            if requestID == chartRequestID {
                isLoadingPairChart = false
            }
        }

        let chart = await marketDataService.pairChart(
            base: draft.fromAsset.coinMeta,
            quote: draft.toAsset.coinMeta,
            range: chartRange,
            currency: currency
        )

        // A superseded request must not publish: a slow ALL fetch landing after
        // the user has switched back to 1M would replace the series under them.
        guard requestID == chartRequestID else { return }
        pairChart = chart
    }

    /// Set the order's lifetime, clamped to what THORChain will honour.
    ///
    /// Clamping on the way IN (rather than only at validation) keeps the form
    /// self-consistent: the pill row, the memo and the queue then all agree on
    /// one number, instead of the UI showing a duration the chain quietly
    /// shortened.
    func selectExpiryBlocks(_ blocks: Int) {
        draft.expiryBlocks = clampLimitExpiryBlocks(blocks, maxBlocks: maxExpiryBlocks)
    }

    func toggleDisplayUnit() {
        draft.displayUnit = (draft.displayUnit == .usd) ? .asset : .usd
    }

    func selectFromAsset(_ asset: LimitSwapAsset) {
        draft.fromAsset = asset
        // The stated amount referred to the previous pair — a desired output in
        // the old target asset means nothing in the new one, and a source amount
        // derived from it was scaled to the old source's decimals. Hand control
        // back to the Sell side rather than silently reinterpreting either.
        draft.amountDriver = .sell
        draft.desiredTargetOutput = 0
        // Pair changed; the cached market price is stale and any prior
        // preset/manual selection no longer applies. The network-fee estimate is
        // per-source too — drop it so a fee for the previous source can't be
        // snapshotted into the order.
        marketPriceRef = nil
        // Pair changed — the prior pair's routability verdict no longer applies;
        // clear it so the CTA isn't stale-blocked until the new probe resolves.
        pairUnroutableReason = nil
        // Invalidate any in-flight market fetch SYNCHRONOUSLY so a previous
        // pair's `refreshMarketPrice` can't land its result during the debounce
        // sleep and repopulate `marketPriceRef` for the wrong pair.
        marketPriceRequestID = UUID()
        invalidateNetworkFeeEstimate()
        invalidatePairChart()
    }

    func selectToAsset(_ asset: LimitSwapAsset) {
        draft.toAsset = asset
        // The stated amount referred to the previous pair — a desired output in
        // the old target asset means nothing in the new one, and a source amount
        // derived from it was scaled to the old source's decimals. Hand control
        // back to the Sell side rather than silently reinterpreting either.
        draft.amountDriver = .sell
        draft.desiredTargetOutput = 0
        marketPriceRef = nil
        // Pair changed — clear the prior routability verdict (see selectFromAsset).
        pairUnroutableReason = nil
        marketPriceRequestID = UUID()
        invalidateNetworkFeeEstimate()
        invalidatePairChart()
    }

    // MARK: - Async actions

    /// Fetch the current market price for the current pair. Stores into
    /// `marketPriceRef` on success; sets `marketPriceError` on failure (does
    /// not clobber the previous reference).
    ///
    /// Quote uses the user's `sourceAmount` when > 0, otherwise substitutes a
    /// fixed-fiat-notional probe (`marketProbeAmount`, ~$100 of the source) so a
    /// cheap source still gets a quote back. This lets the view seed a market
    /// reference *before* the user types an amount so the Market pill and
    /// target-price auto-seed work on first paint.
    /// Fetch the live THORChain inbound list and compute the routable set.
    /// On fetch failure or empty result, falls back to the static set
    /// derived from our prefix table — so the picker always has *some*
    /// non-empty filter rather than silently allowing every chain.
    func refreshSupportedChains() async {
        // Route the fetch through the injected interactor (not
        // `ThorchainService.shared`) so this is unit-testable, and delegate the
        // halt-filtering + fallback to the pure `computeSupportedChains`.
        let inbounds = await interactor.fetchInboundAddresses()
        let chains = computeSupportedChains(from: inbounds)
        supportedChains = chains
        logger.info("refreshSupportedChains: \(chains.count, privacy: .public) routable chains")
    }

    /// Resolve THORChain's Advanced Swap Queue availability (`EnableAdvSwapQueue`
    /// mimir) and cache it into `advancedSwapQueueEnabled`. Fail-closed: the
    /// interactor returns `false` on any fetch/parse failure, so a network blip
    /// leaves placement blocked rather than letting a `=<` order through on a
    /// network that would treat it as a market swap.
    func refreshAdvancedSwapQueueGate() async {
        advancedSwapQueueEnabled = await interactor.isAdvancedSwapQueueEnabled()
        logger.info("EnableAdvSwapQueue gate resolved: \(self.advancedSwapQueueEnabled == true, privacy: .public)")
    }

    /// Resolve the live TTL ceiling and re-clamp the current draft against it.
    ///
    /// Re-clamping matters when the fetched cap is LOWER than the default the
    /// draft was seeded with: the draft may already hold an expiry the chain
    /// would now silently shorten, and leaving it would show a duration the
    /// order never gets. Raising the cap never invalidates an existing choice,
    /// so the clamp is a no-op in that direction.
    func refreshMaxExpiry() async {
        maxExpiryBlocks = await interactor.fetchLimitSwapMaxAgeBlocks()
        isMaxExpiryResolved = true
        draft.expiryBlocks = clampLimitExpiryBlocks(draft.expiryBlocks, maxBlocks: maxExpiryBlocks)
        logger.info("StreamingLimitSwapMaxAge resolved: \(self.maxExpiryBlocks, privacy: .public) blocks")
    }

    func refreshMarketPrice() async {
        let requestID = UUID()
        marketPriceRequestID = requestID

        guard let fromMemo = draft.fromAsset.memoSymbol,
              let toMemo = draft.toAsset.memoSymbol else {
            logger.warning("refreshMarketPrice: missing memo symbol — from=\(self.draft.fromAsset.ticker, privacy: .public) to=\(self.draft.toAsset.ticker, privacy: .public)")
            marketPriceRef = nil
            // An asset with no memo-asset encoding can't be placed — surface it
            // and block the CTA rather than let a dead tap through.
            pairUnroutableReason = .unsupportedAsset
            return
        }
        guard let destAddress = destinationAddress() else {
            logger.error("refreshMarketPrice: no destination address for target chain \(self.draft.toAsset.chain.name, privacy: .public)")
            marketPriceError = ViewModelError.noDestinationAddressForTargetChain
            return
        }
        let quoteAmount = marketProbeAmount(
            sourceAmount: draft.sourceAmount,
            sourceDecimals: draft.fromAsset.decimals,
            sourceFiatPricePerUnit: sourceUsdPricePerUnit
        )

        isLoadingMarketPrice = true
        marketPriceError = nil
        defer {
            // Only the most-recent request clears the loading flag — older
            // ones must not flip a brand-new in-flight request's spinner off.
            if requestID == marketPriceRequestID {
                isLoadingMarketPrice = false
            }
        }
        do {
            let price = try await interactor.fetchMarketPrice(
                sourceAsset: fromMemo,
                sourceAmount: quoteAmount,
                sourceDecimals: draft.fromAsset.decimals,
                targetAsset: toMemo,
                targetDecimals: draft.toAsset.decimals,
                destinationAddress: destAddress
            )
            // Guard against stale-response overwrites: if a newer request
            // started while this one was awaiting, drop our result.
            guard requestID == marketPriceRequestID else { return }
            marketPriceRef = price
            // A successful quote proves the pair is routable (a pool exists).
            pairUnroutableReason = nil
            logger.info("refreshMarketPrice: \(fromMemo, privacy: .public) → \(toMemo, privacy: .public) = \(price.description, privacy: .public)")
        } catch {
            guard requestID == marketPriceRequestID else { return }
            marketPriceError = error
            // Classify a NO-POOL refusal specifically. `ThorchainSwapError` is
            // just THORNode's structured error envelope (it also carries
            // amount/dust/fee/halt failures), so keying `.noRoute` off the type
            // alone would mislabel a valid pair. Route it through the SAME
            // classifier the market swap uses (`SwapService.mapThorchainSwapError`
            // → `.noLiquidityPool` for "pool does not exist" / "invalid symbol" /
            // "bad to|from asset"): only a definitive missing-pool verdict drives
            // the "can't route" row. Any other failure (transient network, dust,
            // a transient halt) leaves `pairUnroutableReason` untouched; placement
            // is still blocked by the missing `marketPriceRef` positive proof,
            // just without a misleading routability message.
            if let swapError = error as? ThorchainSwapError,
               SwapService.mapThorchainSwapError(swapError) == .noLiquidityPool {
                pairUnroutableReason = .noRoute
            }
            logger.error("refreshMarketPrice failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Refresh `networkFeeEstimate` for the current source/target + amount. Kicked
    /// by the view on load / asset change / amount change, mirroring
    /// `refreshMarketPrice`. No-op until an amount is entered (the fee is only
    /// needed for a placeable order, and a 0-amount UTXO plan can't be built).
    /// Fail-soft: a transient fetch error keeps the previous estimate rather than
    /// zeroing it. Stale results are dropped via the request-ID guard.
    func refreshNetworkFeeEstimate(sourceCoin: Coin, targetCoin: Coin) async {
        guard draft.sourceAmount > 0 else { return }
        let requestID = UUID()
        networkFeeRequestID = requestID
        do {
            let fee = try await interactor.estimateNetworkFee(
                sourceCoin: sourceCoin,
                targetCoin: targetCoin,
                sourceAmount: draft.sourceAmount,
                vault: vault
            )
            guard requestID == networkFeeRequestID else { return }
            networkFeeEstimate = fee
            logger.info("refreshNetworkFeeEstimate: \(sourceCoin.ticker, privacy: .public) fee=\(fee.description, privacy: .public)")
        } catch {
            guard requestID == networkFeeRequestID else { return }
            logger.warning("refreshNetworkFeeEstimate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pair change: debounced, coalesced refresh of the market price + network
    /// fee (run concurrently — they're independent) plus a Market-preset re-seed.
    /// Cancels the prior pair refresh so a swap's two coin mutations collapse into
    /// one round of fetches, and cancels any pending amount fee fetch that is now
    /// stale for the new pair.
    func schedulePairRefresh(sourceCoin: Coin, targetCoin: Coin, currency: SettingsCurrency) {
        pairRefreshTask?.cancel()
        feeRefreshTask?.cancel()
        let editSeqAtSchedule = targetPriceEditSeq
        pairRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.inputDebounce)
            guard !Task.isCancelled, let self else { return }
            async let market: Void = self.refreshMarketPrice()
            async let fee: Void = self.refreshNetworkFeeEstimate(sourceCoin: sourceCoin, targetCoin: targetCoin)
            async let chart: Void = self.refreshPairChart(currency: currency)
            _ = await (market, fee, chart)
            // Only auto-seed the Market preset if the user hasn't chosen a price
            // (typed edit OR preset tap) since this refresh was scheduled —
            // otherwise the delayed seed would clobber their choice.
            guard !Task.isCancelled, self.targetPriceEditSeq == editSeqAtSchedule else { return }
            self.selectPresetPct(0, userInitiated: false)
        }
    }

    /// Amount change: debounced fee-only refresh (a keystroke burst collapses into
    /// one fetch). Never touches the market price / preset, so typing an amount
    /// can't reset the user's target price.
    func scheduleFeeEstimate(sourceCoin: Coin, targetCoin: Coin) {
        feeRefreshTask?.cancel()
        feeRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.inputDebounce)
            guard !Task.isCancelled, let self else { return }
            await self.refreshNetworkFeeEstimate(sourceCoin: sourceCoin, targetCoin: targetCoin)
        }
    }

    // MARK: - Place flow

    /// Assemble a placeable limit order from the current draft: run the shared
    /// input validation, build + byte-cap the memo, and construct the persisted
    /// `LimitOrderRecord`. Returns `nil` when the order can't be placed; for
    /// user-actionable failures it also sets `placeOrderError` so the view can
    /// surface an alert. The view turns a non-nil result into a
    /// `SwapTransaction` and routes to the shared Verify screen.
    ///
    /// Business logic lives here (not in the view) so it is unit-testable: the
    /// previous live path built the memo inline in the entry view and never ran
    /// `validateLimitSwapInputs`, so validation only executed in dead code.
    func preparePlaceableOrder() -> (memo: String, record: LimitOrderRecord)? {
        // "Not ready yet" rather than a user-actionable error: the CTA is disabled
        // while amount/price are 0. Return silently — no alert.
        guard draft.sourceAmount > 0, draft.targetPrice > 0 else {
            return nil
        }
        // A tappable CTA must NEVER silently no-op. If the pair can't be encoded
        // to a THORChain memo asset (per-ASSET routability — the picker only
        // filters per-CHAIN, so e.g. a THOR token with no pool slips through) or
        // no destination address resolves for the target chain, surface an alert.
        // `canPlaceOrder` also disables the CTA on these, so this is the belt to
        // that suspenders — a stale-state tap still gets feedback.
        guard let sourceAsset = draft.fromAsset.memoSymbol,
              let targetAsset = draft.toAsset.memoSymbol,
              let destAddress = destinationAddress() else {
            logger.error("Place order rejected: pair not placeable (memoSymbol/dest nil) — from=\(self.draft.fromAsset.ticker, privacy: .public) to=\(self.draft.toAsset.ticker, privacy: .public)")
            placeOrderError = .pairNotPlaceable
            return nil
        }

        // Belt to `canPlaceOrder`'s suspenders: a pair the market-price probe
        // flagged as unroutable (no THORChain pool) — OR one the probe hasn't yet
        // proven routable (`marketPriceRef == nil`) — must never assemble, even if
        // a stale/direct call slipped past the disabled CTA. Requiring the
        // positive `marketPriceRef` proof here (not just the absence of a known
        // verdict) fully closes the pre-probe window, so a poolless `=<` order can
        // never reach Verify and rest unfillable.
        guard pairUnroutableReason == nil, marketPriceRef != nil else {
            logger.error("Place order rejected: pair unroutable/unproven (reason=\(String(describing: self.pairUnroutableReason), privacy: .public), hasMarketRef=\(self.marketPriceRef != nil, privacy: .public))")
            placeOrderError = .pairNotPlaceable
            return nil
        }

        // Availability gate (FAIL-CLOSED): THORChain's Advanced Swap Queue must
        // be confirmed live before a resting `=<` order can be placed. When the
        // `EnableAdvSwapQueue` mimir isn't a confirmed `1` — including while the
        // gate is still unresolved (`nil`) or the fetch failed — block placement.
        // A `=<` order on a network with the queue disabled can be treated as a
        // market swap and execute immediately at the wrong price (fund-safety),
        // so silently allowing it is not acceptable.
        guard advancedSwapQueueEnabled == true else {
            logger.error("Place order rejected: EnableAdvSwapQueue mimir not confirmed enabled (value: \(String(describing: self.advancedSwapQueueEnabled), privacy: .public))")
            placeOrderError = .advancedSwapQueueDisabled
            return nil
        }

        // Real affiliate config: read the vault's referral code (if any) and
        // compute the affiliate fragment via the same helper the market path
        // uses. Vault-tier discount defaults to 0 for Phase 1.
        let referralCode = vault.referralCode?.code ?? ""
        let (affiliate, affiliateBps) = ThorchainService.affiliateParams(
            referredCode: referralCode,
            discountBps: 0
        )

        let inputs = LimitSwapInputs(
            sourceAsset: sourceAsset,
            sourceAmount: draft.sourceAmount,
            sourceDecimals: draft.fromAsset.decimals,
            targetAsset: targetAsset,
            destAddress: destAddress,
            targetPrice: draft.targetPrice,
            expiryBlocks: draft.expiryBlocks,
            affiliate: affiliate ?? THORChainSwaps.affiliateFeeAddress,
            affiliateBps: affiliateBps ?? String(THORChainSwaps.affiliateFeeRateBp)
        )

        // Run the shared input validation in production. Previously the live
        // path built the memo directly and skipped this gate entirely.
        let validationErrors = validateLimitSwapInputs(inputs, maxExpiryBlocks: maxExpiryBlocks)
        guard validationErrors.isEmpty else {
            logger.error("Place order rejected: validation failed \(String(describing: validationErrors), privacy: .public)")
            placeOrderError = .invalidInputs(validationErrors)
            return nil
        }

        // Memo assembly + byte-cap fitting. Can fail for genuinely
        // user-actionable reasons (a target price that overflows the LIM
        // fixed-point, or a memo that still overflows the source chain's per-tx
        // byte budget even after bounded LIM round-up). These must surface via an
        // alert, not be swallowed silently. `buildFittedLimitSwapMemo` returns the
        // effective LIM actually encoded so the displayed minimum matches the
        // signed order.
        let memo: String
        let effectiveMinOutput: Decimal
        // The EFFECTIVE LIM, not the `targetPrice`-derived one: when byte-fitting
        // rounds the LIM up, the rounded value is what the memo carries and
        // therefore what THORChain indexes the order by. A future cancel has to
        // reproduce it exactly or it addresses a bucket the order isn't in.
        let signedTradeTarget: BigInt
        do {
            let fitted = try buildFittedLimitSwapMemo(
                inputs,
                sourceChainKind: draft.fromAsset.chain.chainType
            )
            memo = fitted.memo
            effectiveMinOutput = limNaturalOutput(fitted.effectiveLim)
            signedTradeTarget = fitted.effectiveLim
        } catch let error as LimitSwapMemoError {
            switch error {
            case let .memoExceedsByteLimit(actual, limit):
                logger.error("Place order rejected: memo \(actual) bytes exceeds \(limit)-byte cap")
                placeOrderError = .memoTooLong(actual: actual, limit: limit)
            case .targetPriceOverflow:
                logger.error("Place order rejected: target price overflowed LIM fixed-point")
                placeOrderError = .targetPriceOverflow
            case .limitAmountTooSmall:
                logger.error("Place order rejected: LIM truncated to zero (amount/price too small)")
                placeOrderError = .limitAmountTooSmall
            }
            return nil
        } catch {
            logger.error("Place order rejected: \(error.localizedDescription, privacy: .public)")
            placeOrderError = .targetPriceOverflow
            return nil
        }

        let record = LimitOrderRecord(
            inboundTxHash: "",  // Filled in by the Done screen after broadcast.
            sourceAsset: sourceAsset,
            sourceAmount: draft.sourceAmount.description,
            sourceDecimals: draft.fromAsset.decimals,
            targetAsset: targetAsset,
            destAddress: destAddress,
            targetPrice: draft.targetPrice,
            expiryBlocks: draft.expiryBlocks,
            createdAt: Date(),
            status: .pending,
            memo: memo,
            minOutputOverride: effectiveMinOutput,
            // Captured here because this is the only moment all three are known
            // exactly. `sourceAmount` on the record is in the coin's NATIVE
            // decimals; THORChain indexes the order in 1e8, and the same
            // conversion the quote endpoint uses is the one the chain applies.
            sourceAmount1e8: ThorchainService.thorchainQuoteAmount(
                sourceAmount: draft.sourceAmount,
                sourceDecimals: draft.fromAsset.decimals
            ).description,
            tradeTarget: signedTradeTarget.description,
            // The same two assets, spelled with their FULL contract address.
            // `sourceAsset`/`targetAsset` above carry the placement spelling,
            // which truncates an EVM contract to 6 characters — correct there
            // (THORNode fuzzy-matches it) and fatal in a cancel, which is the
            // one inbound memo type that skips fuzzy matching. The truncation is
            // irreversible, so the long form has to be taken here, while the
            // contract address is still in hand.
            sourceAssetFull: draft.fromAsset.cancelMemoSymbol,
            targetAssetFull: draft.toAsset.cancelMemoSymbol,
            sourceChainRawValue: draft.fromAsset.chain.rawValue
        )
        return (memo, record)
    }

    // MARK: - Computed UI state

    /// Memoizes `expectedBuyAmount` keyed on its three inputs, so a render-path
    /// read doesn't re-run `computeLim` (BigInt.power + Decimal↔BigInt) on every
    /// view-body evaluation / crossfade frame. `@ObservationIgnored` so writing
    /// the cache inside the getter can't trip the observation machinery.
    @ObservationIgnored
    private var expectedBuyAmountCache: (amount: BigInt, decimals: Int, price: Decimal, value: Decimal)?

    /// Expected buy (target) amount for the current draft, derived from the SAME
    /// truncated `computeLim` the signed memo's LIM uses — so the Asset-section
    /// preview can never diverge (higher) from what the order actually
    /// guarantees. `0` when not yet computable. Business math stays out of the
    /// view. Memoized on `(sourceAmount, sourceDecimals, targetPrice)`.
    var expectedBuyAmount: Decimal {
        let amount = draft.sourceAmount
        let decimals = draft.fromAsset.decimals
        let price = draft.targetPrice
        if let cache = expectedBuyAmountCache,
           cache.amount == amount, cache.decimals == decimals, cache.price == price {
            return cache.value
        }
        let value = limitOrderExpectedOutput(
            sourceAmount: amount,
            sourceDecimals: decimals,
            targetPrice: price
        )
        expectedBuyAmountCache = (amount, decimals, price, value)
        return value
    }

    /// Percentage above (positive) or below (negative) the current market.
    /// Returns 0 when the market reference is unset.
    var pctFromMarket: Decimal {
        guard let market = marketPriceRef else { return 0 }
        return computePctFromMarket(targetPrice: draft.targetPrice, marketPrice: market)
    }

    /// `priceAtOrBelowMarket` when the user's target ≤ market;
    /// `priceFarAboveMarket` when target > 1.2 × market;
    /// `nil` otherwise (or when market reference is unset).
    var displayedWarning: LimitSwapWarning? {
        guard let market = marketPriceRef else { return nil }
        return evaluateWarning(targetPrice: draft.targetPrice, marketPrice: market)
    }

    // MARK: - Vault lookups

    /// User's destination address on the target chain — looked up from their
    /// vault. The keysign payload's recipient is the THORChain inbound vault,
    /// not this address; this is what gets embedded in the limit memo.
    ///
    /// Falls back to **any** coin on the target chain when an exact (chain +
    /// ticker + contract) match isn't held. EVM / Cosmos / UTXO addresses are
    /// per-chain, not per-token, so the fallback resolves the user's address
    /// even if they don't currently hold the exact target asset (e.g. they
    /// hold ETH but want to receive USDC on Ethereum — same address).
    func destinationAddress() -> String? {
        if let exact = vault.coins.first(where: { coin in
            coin.chain == draft.toAsset.chain
            && coin.ticker == draft.toAsset.ticker
            && coin.contractAddress == draft.toAsset.contractAddress
        })?.address {
            return exact
        }
        return vault.coins.first(where: { $0.chain == draft.toAsset.chain })?.address
    }

    enum ViewModelError: Error, Equatable {
        case noDestinationAddressForTargetChain
    }
}
