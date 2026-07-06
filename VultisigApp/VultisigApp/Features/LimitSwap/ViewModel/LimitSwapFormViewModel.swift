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
