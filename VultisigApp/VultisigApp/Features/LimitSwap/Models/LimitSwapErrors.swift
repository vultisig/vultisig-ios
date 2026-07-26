//
//  LimitSwapErrors.swift
//  VultisigApp
//

import Foundation

enum LimitSwapValidationError: Error, Equatable {
    case sourceAmountNotPositive
    case targetPriceNotPositive
    case expiryHoursUnsupported(Int)
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
        }
    }
}
