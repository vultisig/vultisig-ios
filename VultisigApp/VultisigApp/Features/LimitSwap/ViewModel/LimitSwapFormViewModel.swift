//
//  LimitSwapFormViewModel.swift
//  VultisigApp
//

import BigInt
import Foundation
import Observation

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

    var isLoadingMarketPrice = false
    var marketPriceError: Error?

    private let vault: Vault
    private let interactor: LimitSwapInteractor

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
    }

    /// Set the target price from a preset pill (`Market`/`+1%`/`+5%`/`+10%`).
    /// No-op if `marketPriceRef` is unset (preset is meaningless without a base).
    func selectPresetPct(_ pct: Int) {
        guard let market = marketPriceRef else { return }
        draft.targetPrice = computePresetPrice(marketPrice: market, pctAboveMarket: pct)
    }

    func selectExpiryHours(_ hours: Int) {
        draft.expiryHours = hours
    }

    func toggleDisplayUnit() {
        draft.displayUnit = (draft.displayUnit == .usd) ? .asset : .usd
    }

    func selectFromAsset(_ asset: LimitSwapAsset) {
        draft.fromAsset = asset
        // Pair changed; the cached market price is stale.
        marketPriceRef = nil
    }

    func selectToAsset(_ asset: LimitSwapAsset) {
        draft.toAsset = asset
        marketPriceRef = nil
    }

    // MARK: - Async actions

    /// Fetch the current market price for the current pair. Stores into
    /// `marketPriceRef` on success; sets `marketPriceError` on failure (does
    /// not clobber the previous reference).
    func refreshMarketPrice() async {
        guard let fromMemo = draft.fromAsset.memoSymbol,
              let toMemo = draft.toAsset.memoSymbol,
              draft.sourceAmount > 0 else {
            marketPriceRef = nil
            return
        }
        guard let destAddress = destinationAddress() else {
            marketPriceError = ViewModelError.noDestinationAddressForTargetChain
            return
        }
        isLoadingMarketPrice = true
        marketPriceError = nil
        defer { isLoadingMarketPrice = false }
        do {
            let price = try await interactor.fetchMarketPrice(
                sourceAsset: fromMemo,
                sourceAmount: draft.sourceAmount,
                sourceDecimals: draft.fromAsset.decimals,
                targetAsset: toMemo,
                targetDecimals: draft.toAsset.decimals,
                destinationAddress: destAddress
            )
            marketPriceRef = price
        } catch {
            marketPriceError = error
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
    func destinationAddress() -> String? {
        vault.coins.first(where: { coin in
            coin.chain == draft.toAsset.chain
            && coin.ticker == draft.toAsset.ticker
            && coin.contractAddress == draft.toAsset.contractAddress
        })?.address
    }

    enum ViewModelError: Error, Equatable {
        case noDestinationAddressForTargetChain
    }
}
