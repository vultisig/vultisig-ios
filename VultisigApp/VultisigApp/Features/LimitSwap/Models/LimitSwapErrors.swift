//
//  LimitSwapErrors.swift
//  VultisigApp
//

import Foundation

enum LimitSwapValidationError: Error, Equatable {
    case sourceAmountNotPositive
    case targetPriceNotPositive
    /// The chosen lifetime falls outside what THORChain will honour. Carries the
    /// bounds because the ceiling is read from a mimir and can move, so a message
    /// that hard-codes "3 days" would eventually be wrong.
    case expiryOutOfRange(blocks: Int, minBlocks: Int, maxBlocks: Int)
    case destAddressEmpty
    case sourceAssetMalformed(String)
    case targetAssetMalformed(String)
    /// Source and target resolve to the SAME THORChain memo asset. A `=<` order
    /// swapping an asset for itself (e.g. `BTC.BTC` → `BTC.BTC`) is impossible;
    /// THORChain refunds it minus the network fee. Reject before the memo is
    /// built so the user never wastes a broadcast.
    case sourceEqualsTarget(String)
}

enum LimitSwapMemoError: Error, Equatable {
    case memoExceedsByteLimit(actual: Int, limit: Int)
    /// The target price (scaled to THORChain's 1e8 fixed-point LIM) overflowed
    /// `Decimal`/`BigInt` and could not be represented. This MUST fail loud:
    /// a silent fallback to `LIM=0` tells THORChain "fill at ANY price", the
    /// exact opposite of a limit order — a fund-safety hazard.
    case targetPriceOverflow
    /// The order is so small that the LIM (minimum output) truncates to zero in
    /// THORChain's 1e8 fixed-point — e.g. a dust source amount, or a very low
    /// target price against a high-decimal source. A `LIM=0` memo means "fill at
    /// ANY price"; the overflow guard covers the large-price direction, this
    /// covers the underflow direction. Same fund-safety hazard, so it MUST also
    /// fail loud rather than emit a price-blind order.
    case limitAmountTooSmall
}

enum LimitSwapQuoteError: Error, Equatable {
    /// THORChain returned an `expected_amount_out` that didn't parse as Decimal.
    case invalidExpectedAmount(String)
    /// The source amount couldn't be expressed as Decimal — typically a
    /// programmer error (BigInt → string round-trip should always succeed).
    case invalidSourceAmount(String)
    /// Source amount resolved to zero in natural units; no quote is meaningful.
    case zeroSourceAmount
}

enum LimitSwapWarning: Equatable {
    case priceAtOrBelowMarket
    case priceFarAboveMarket
}

/// Why the currently-selected pair can't be placed as a resting `=<` order.
/// Derived from the form's market-price probe: either a selected asset that has
/// no THORChain memo-asset encoding, or a pair THORChain refuses to quote (no
/// pool for the pair, or trading paused). Drives the inline "can't route" row
/// and disables the Place CTA so a poolless pair (e.g. RUNE→VULT, KUJI→ETH)
/// never reaches the Verify screen and rests as an unfillable order. Distinct
/// from a transient network `marketPriceError`, which does NOT block placement.
enum LimitSwapPairUnroutableReason: Equatable {
    /// One side of the pair has no THORChain memo-asset encoding — the asset
    /// isn't supported for limit orders (its `memoSymbol` is `nil`).
    case unsupportedAsset
    /// THORChain refused to quote the pair — there is no pool for the pair, or
    /// trading is currently paused. Surfaced from a `ThorchainSwapError` thrown
    /// by the market-price probe.
    case noRoute

    /// Localized, user-readable message for the inline row.
    var message: String {
        switch self {
        case .unsupportedAsset:
            return "limitSwap.error.unsupportedAsset".localized
        case .noRoute:
            return "limitSwap.error.pairNotRoutable".localized
        }
    }
}

/// Whether the vault can afford the sell amount the limit form currently holds.
///
/// Derived from the SAME rule the market swap gates Continue on
/// (`SwapCryptoLogic.balanceError`), so the two swap tabs can never disagree for
/// identical input. This type only names the verdict and the asset it is about;
/// the affordability arithmetic lives entirely in `SwapCryptoLogic`.
enum LimitSwapBalanceState: Equatable {
    /// The sell amount, and the network fee on top of it, both fit.
    case sufficient
    /// The sell amount alone exceeds the source balance. Knowable WITHOUT a
    /// resolved network fee, so it is shown the moment the amount is typed.
    case insufficientFunds(sourceTicker: String)
    /// The sell amount fits, but the network fee does not — either it no longer
    /// fits alongside the amount (source coin pays its own gas) or the native
    /// fee sibling can't cover it (an ERC20 source pays ETH). Only ever produced
    /// from a RESOLVED fee estimate.
    case insufficientGas(feeTicker: String)
    /// Nothing can be concluded yet: the network-fee estimate is still in flight
    /// (so gas coverage is unjudgeable), or the selected coin and the draft's
    /// source asset have not re-synced after a pair change. Renders NO row and
    /// blocks placement — the form never shows a gas error it would have to take
    /// back one frame later.
    case indeterminate

    /// Whether this verdict must keep the Place Order button disabled. Only an
    /// affirmative `sufficient` unblocks it, so both failure modes and the
    /// not-yet-known state all fail closed.
    var blocksPlacement: Bool { self != .sufficient }

    /// Message for the inline notice row, or `nil` when there is nothing honest
    /// to say — the order is affordable, or the verdict isn't in yet.
    var noticeMessage: String? {
        switch self {
        case .sufficient, .indeterminate:
            return nil
        case let .insufficientFunds(sourceTicker):
            return String(format: "limitSwap.error.insufficientFunds".localized, sourceTicker)
        case let .insufficientGas(feeTicker):
            return String(format: "limitSwap.error.insufficientGas".localized, feeTicker)
        }
    }
}

/// User-facing failure surfaced when "Place Order" cannot assemble a valid
/// order. Carries a localized message so the entry view can show an alert
/// instead of silently doing nothing. `Identifiable` so it can back a SwiftUI
/// `.alert(item:)`.
enum LimitSwapPlaceOrderError: Error, Equatable, Identifiable {
    /// The assembled memo exceeds the source chain's per-tx byte budget.
    case memoTooLong(actual: Int, limit: Int)
    /// The target price overflowed when scaled to THORChain's fixed-point LIM.
    case targetPriceOverflow
    /// The order's minimum output (LIM) truncates to zero — the amount/price is
    /// too small to place a price-bound order.
    case limitAmountTooSmall
    /// The shared input validation (`validateLimitSwapInputs`) rejected the
    /// draft before the memo was built. The live "Place Order" path runs this
    /// gate in production so malformed inputs surface as an alert instead of
    /// building a memo from bad data.
    case invalidInputs([LimitSwapValidationError])
    /// The `EnableAdvSwapQueue` THORChain mimir is not confirmed enabled, so
    /// resting limit orders (`=<`) are not currently accepted by the network.
    /// Fail CLOSED — placing anyway risks the order being treated as a market
    /// swap or rejected on-chain.
    case advancedSwapQueueDisabled
    /// The selected pair can't be assembled into a placeable order — one side has
    /// no THORChain memo-asset encoding, or no destination address could be
    /// resolved for the target chain. The CTA is also disabled on these via
    /// `canPlaceOrder`, so this is the belt-and-suspenders that guarantees a tap
    /// can never silently no-op (previously these guards `return nil`ed silently).
    case pairNotPlaceable
    /// The `StreamingLimitSwapMaxAge` mimir hasn't resolved yet, so the TTL the
    /// draft would be validated against is still the seed rather than the
    /// network's. Fail CLOSED — the seed is a plausible value, not a true one,
    /// and a chain that caps lower would silently shorten the order.
    case expiryCeilingUnresolved

    var id: String {
        switch self {
        case let .memoTooLong(actual, limit):
            return "memoTooLong-\(actual)-\(limit)"
        case .targetPriceOverflow:
            return "targetPriceOverflow"
        case .limitAmountTooSmall:
            return "limitAmountTooSmall"
        case let .invalidInputs(errors):
            return "invalidInputs-\(errors.map(String.init(describing:)).joined(separator: ","))"
        case .advancedSwapQueueDisabled:
            return "advancedSwapQueueDisabled"
        case .pairNotPlaceable:
            return "pairNotPlaceable"
        case .expiryCeilingUnresolved:
            return "expiryCeilingUnresolved"
        }
    }

    /// Localized, user-readable description for the alert body.
    var message: String {
        switch self {
        case let .memoTooLong(actual, limit):
            return String(
                format: "limitSwap.confirmation.byteCapError.format".localized,
                actual,
                limit
            )
        case .targetPriceOverflow:
            return "limitSwap.error.targetPriceOverflow".localized
        case .limitAmountTooSmall:
            return "limitSwap.error.limitAmountTooSmall".localized
        case .invalidInputs:
            return "limitSwap.error.invalidInputs".localized
        case .advancedSwapQueueDisabled:
            return "limitSwap.error.advancedSwapQueueDisabled".localized
        case .pairNotPlaceable:
            // Reuses the routability-gate copy: the actionable ask is identical —
            // pick a different asset THORChain can route.
            return "limitSwap.error.pairNotRoutable".localized
        case .expiryCeilingUnresolved:
            return "limitSwap.error.expiryCeilingUnresolved".localized
        }
    }
}
