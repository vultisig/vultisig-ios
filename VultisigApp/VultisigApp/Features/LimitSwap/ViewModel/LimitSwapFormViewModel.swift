//
//  LimitSwapFormViewModel.swift
//  VultisigApp
//

import BigInt
import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "limit-swap-form")

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

    /// Tracks the preset that last set `draft.targetPrice`. `nil` after a
    /// manual edit (typed input). Used by the dynamic Market pill to render
    /// statically ("Market") whenever a preset is the live source — and only
    /// flip into the rounded-pct + reset affordance after a manual edit.
    var lastPresetPct: Int?

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

    /// Whether the current draft can be placed — gates the entry screen's Place
    /// Order button. Requires a positive amount + target price, the Advanced Swap
    /// Queue confirmed live, AND a RESOLVED network-fee estimate
    /// (`networkFeeEstimate > 0`). Gating on the resolved fee closes a
    /// fee-disclosure race: the estimate is dropped to `0` on every input change
    /// and re-fetched asynchronously, so without this the user could tap Place
    /// before it resolves and sign an order whose Verify / Done screens show a
    /// blank network-fee row — never seeing the real source-chain gas that is
    /// derived at sign time. While the fee recomputes the button stays disabled.
    var canPlaceOrder: Bool {
        draft.targetPrice > 0
            && draft.sourceAmount > 0
            && isAdvancedSwapQueueEnabled
            && networkFeeEstimate > 0
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

    /// Keystroke/selection debounce before the market-price / fee fetches fire.
    static let inputDebounce: Duration = .milliseconds(300)

    init(initialDraft: LimitSwapDraft, vault: Vault, interactor: LimitSwapInteractor) {
        self.draft = initialDraft
        self.vault = vault
        self.interactor = interactor
    }

    // MARK: - User input mutations

    func amountChanged(_ amount: BigInt) {
        draft.sourceAmount = amount
        // The network fee (UTXO especially) is amount-dependent; drop the stale
        // estimate so a fee from a previous amount can never be snapshotted into
        // the placed order. A fresh estimate is re-fetched by the view.
        invalidateNetworkFeeEstimate()
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
        lastPresetPct = nil
        // A manual edit: a pending pair refresh must not overwrite it with the
        // delayed Market preset.
        targetPriceEditSeq += 1
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
    /// stable (formatter caps at 8; without rounding, parse(format(x)) != x
    /// for high-precision quotes and the sync would clobber `lastPresetPct`).
    /// `userInitiated` is `true` for a preset PILL tap (a deliberate price
    /// selection that must not be overwritten by a pending auto-seed) and `false`
    /// for the programmatic Market auto-seed (on load / pair change).
    func selectPresetPct(_ pct: Int, userInitiated: Bool = true) {
        guard let market = marketPriceRef else { return }
        let raw = computePresetPrice(marketPrice: market, pctAboveMarket: pct)
        var rounded = Decimal()
        var input = raw
        NSDecimalRound(&rounded, &input, 8, .plain)
        draft.targetPrice = rounded
        lastPresetPct = pct
        if userInitiated {
            // A user's preset selection is a price choice — a pending pair
            // refresh's delayed Market auto-seed must not clobber it.
            targetPriceEditSeq += 1
        }
    }

    func selectExpiryHours(_ hours: Int) {
        draft.expiryHours = hours
    }

    func toggleDisplayUnit() {
        draft.displayUnit = (draft.displayUnit == .usd) ? .asset : .usd
    }

    func selectFromAsset(_ asset: LimitSwapAsset) {
        draft.fromAsset = asset
        // Pair changed; the cached market price is stale and any prior
        // preset/manual selection no longer applies. The network-fee estimate is
        // per-source too — drop it so a fee for the previous source can't be
        // snapshotted into the order.
        marketPriceRef = nil
        lastPresetPct = nil
        // Pair changed — the prior pair's routability verdict no longer applies;
        // clear it so the CTA isn't stale-blocked until the new probe resolves.
        pairUnroutableReason = nil
        // Invalidate any in-flight market fetch SYNCHRONOUSLY so a previous
        // pair's `refreshMarketPrice` can't land its result during the debounce
        // sleep and repopulate `marketPriceRef` for the wrong pair.
        marketPriceRequestID = UUID()
        invalidateNetworkFeeEstimate()
    }

    func selectToAsset(_ asset: LimitSwapAsset) {
        draft.toAsset = asset
        marketPriceRef = nil
        lastPresetPct = nil
        // Pair changed — clear the prior routability verdict (see selectFromAsset).
        pairUnroutableReason = nil
        marketPriceRequestID = UUID()
        invalidateNetworkFeeEstimate()
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
    func schedulePairRefresh(sourceCoin: Coin, targetCoin: Coin) {
        pairRefreshTask?.cancel()
        feeRefreshTask?.cancel()
        let editSeqAtSchedule = targetPriceEditSeq
        pairRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.inputDebounce)
            guard !Task.isCancelled, let self else { return }
            async let market: Void = self.refreshMarketPrice()
            async let fee: Void = self.refreshNetworkFeeEstimate(sourceCoin: sourceCoin, targetCoin: targetCoin)
            _ = await (market, fee)
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
            expiryHours: draft.expiryHours,
            affiliate: affiliate ?? THORChainSwaps.affiliateFeeAddress,
            affiliateBps: affiliateBps ?? String(THORChainSwaps.affiliateFeeRateBp)
        )

        // Run the shared input validation in production. Previously the live
        // path built the memo directly and skipped this gate entirely.
        let validationErrors = validateLimitSwapInputs(inputs)
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
        do {
            let fitted = try buildFittedLimitSwapMemo(
                inputs,
                sourceChainKind: draft.fromAsset.chain.chainType
            )
            memo = fitted.memo
            effectiveMinOutput = limNaturalOutput(fitted.effectiveLim)
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
            expiryBlocks: computeExpiryBlocks(hours: draft.expiryHours),
            createdAt: Date(),
            status: .pending,
            memo: memo,
            expiryHours: draft.expiryHours,
            minOutputOverride: effectiveMinOutput
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
