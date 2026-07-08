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

    var isLoadingMarketPrice = false
    var marketPriceError: Error?

    /// Whether THORChain's Advanced Swap Queue (`EnableAdvSwapQueue` mimir) is
    /// live, so resting `=<` limit orders are actually accepted on-chain.
    /// `nil` while the gate hasn't been resolved yet. **Fail-closed:** placement
    /// is blocked until this is confirmed `true` (see `preparePlaceableOrder`);
    /// `nil`/`false` both block. Refreshed via `refreshAdvancedSwapQueueGate()`.
    var advancedSwapQueueEnabled: Bool?

    /// Convenience for the view: `true` only when the queue is confirmed live.
    var isAdvancedSwapQueueEnabled: Bool { advancedSwapQueueEnabled == true }

    /// User-facing error raised while assembling / pre-flighting the order in
    /// "Place Order" (memo byte-cap overflow, target-price overflow). Drives an
    /// alert in `LimitSwapEntryView`. `nil` clears the alert. Previously these
    /// failures were swallowed silently — the user tapped "Place Order" and
    /// nothing happened, with no feedback.
    var placeOrderError: LimitSwapPlaceOrderError?

    private let vault: Vault
    private let interactor: LimitSwapInteractor

    /// Tags each in-flight `refreshMarketPrice` so a slower older request
    /// can't overwrite a faster newer one's `marketPriceRef`/`error` after
    /// it lands. Pure UUID ordering — no pointer to the actual Task is
    /// kept, so cancellation is implicit (we just ignore the result).
    private var marketPriceRequestID = UUID()

    init(initialDraft: LimitSwapDraft, vault: Vault, interactor: LimitSwapInteractor) {
        self.draft = initialDraft
        self.vault = vault
        self.interactor = interactor
    }

    // MARK: - User input mutations

    func amountChanged(_ amount: BigInt) {
        draft.sourceAmount = amount
    }

    func targetPriceChanged(_ price: Decimal) {
        draft.targetPrice = price
        lastPresetPct = nil
    }

    /// Set the target price from a preset pill (`Market`/`+1%`/`+5%`/`+10%`).
    /// No-op if `marketPriceRef` is unset (preset is meaningless without a base).
    /// Result is rounded to 8 decimals so the price text↔draft round-trip is
    /// stable (formatter caps at 8; without rounding, parse(format(x)) != x
    /// for high-precision quotes and the sync would clobber `lastPresetPct`).
    func selectPresetPct(_ pct: Int) {
        guard let market = marketPriceRef else { return }
        let raw = computePresetPrice(marketPrice: market, pctAboveMarket: pct)
        var rounded = Decimal()
        var input = raw
        NSDecimalRound(&rounded, &input, 8, .plain)
        draft.targetPrice = rounded
        lastPresetPct = pct
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
        // preset/manual selection no longer applies.
        marketPriceRef = nil
        lastPresetPct = nil
    }

    func selectToAsset(_ asset: LimitSwapAsset) {
        draft.toAsset = asset
        marketPriceRef = nil
        lastPresetPct = nil
    }

    // MARK: - Async actions

    /// Fetch the current market price for the current pair. Stores into
    /// `marketPriceRef` on success; sets `marketPriceError` on failure (does
    /// not clobber the previous reference).
    ///
    /// Quote uses the user's `sourceAmount` when ≥ 1 natural unit, otherwise
    /// substitutes a 1-unit quote (`10^sourceDecimals`). This lets the view
    /// seed a market reference *before* the user types an amount so the
    /// Market pill and target-price auto-seed work on first paint.
    /// Fetch the live THORChain inbound list and compute the routable set.
    /// On fetch failure or empty result, falls back to the static set
    /// derived from our prefix table — so the picker always has *some*
    /// non-empty filter rather than silently allowing every chain.
    func refreshSupportedChains() async {
        let inbounds = await ThorchainService.shared.fetchThorchainInboundAddress()
        var chains: Set<Chain> = [.thorChain]
        for entry in inbounds {
            // Missing pause flags read as "not paused" — same convention as
            // `SwapHaltGate.isHalted(chain:in:)` on the market path.
            guard !entry.halted,
                  !(entry.global_trading_paused ?? false),
                  !(entry.chain_trading_paused ?? false) else { continue }
            if let chain = chainFromThorchainSymbol(entry.chain) {
                chains.insert(chain)
            }
        }
        if chains.count <= 1 {
            // Inbound fetch didn't return useful data — fall back to the
            // static routable set so the picker isn't artificially empty.
            chains = Set(Chain.allCases.filter { isThorchainRoutable(chain: $0) })
        }
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
            return
        }
        guard let destAddress = destinationAddress() else {
            logger.error("refreshMarketPrice: no destination address for target chain \(self.draft.toAsset.chain.name, privacy: .public)")
            marketPriceError = ViewModelError.noDestinationAddressForTargetChain
            return
        }
        let oneUnit = BigInt(10).power(draft.fromAsset.decimals)
        let quoteAmount = max(draft.sourceAmount, oneUnit)

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
            logger.info("refreshMarketPrice: \(fromMemo, privacy: .public) → \(toMemo, privacy: .public) = \(price.description, privacy: .public)")
        } catch {
            guard requestID == marketPriceRequestID else { return }
            marketPriceError = error
            logger.error("refreshMarketPrice failed: \(error.localizedDescription, privacy: .public)")
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
        // Prerequisites that mean "not ready yet" rather than a user-actionable
        // error: the CTA is disabled while amount/price are 0, and unroutable
        // chains are filtered out by the picker (so `memoSymbol` is non-nil).
        // Return silently — no alert.
        guard let sourceAsset = draft.fromAsset.memoSymbol,
              let targetAsset = draft.toAsset.memoSymbol,
              let destAddress = destinationAddress(),
              draft.sourceAmount > 0,
              draft.targetPrice > 0 else {
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

        // Phase 1 routes only native source assets. A non-native (ERC20-style)
        // source would set `toAddress = router` with `approvePayload: nil` and
        // no approve-first keysign, which the THORChain router rejects. The
        // picker filters by chain, not token type, so ETH.USDC is still
        // pickable — guard loudly here. (ERC20 approve-first flow is Phase 2.)
        guard draft.fromAsset.isNativeToken else {
            logger.error("Place order rejected: non-native source \(self.draft.fromAsset.ticker, privacy: .public) not supported in Phase 1")
            placeOrderError = .nonNativeSourceUnsupported
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

        // Memo assembly + byte-cap pre-flight. Both can fail for genuinely
        // user-actionable reasons (a target price that overflows the LIM
        // fixed-point, or a memo that overflows the source chain's per-tx byte
        // budget). These must surface via an alert, not be swallowed silently.
        let memo: String
        do {
            memo = try buildLimitSwapMemo(inputs)
            try assertMemoByteLength(memo, sourceChainKind: draft.fromAsset.chain.chainType)
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
            expiryHours: draft.expiryHours
        )
        return (memo, record)
    }

    // MARK: - Computed UI state

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
