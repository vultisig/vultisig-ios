//
//  LimitOrderDetails.swift
//  VultisigApp
//
//  Value types the tx-history surfaces read a limit order through.
//
//  `LimitOrder` is a `@MainActor @Model` and is the authoritative record, but a
//  view must not hold one across an actor boundary — and, more practically, the
//  Limit Orders tab renders `TransactionHistoryData` rows, which carry no target
//  price, expiry or fill split at all. `LimitOrderDetails` is the snapshot that
//  joins the two, keyed by inbound tx hash.
//
//  The derivations (`fillFraction`, `isPartiallyFilled`, the expiry countdown)
//  live on the small pure types here rather than on the `@Model`, so that the
//  order card, the detail sheet and the model itself all read the same
//  arithmetic instead of three copies of it.
//

import BigInt
import Foundation

// MARK: - Fill split

/// An order's fill accounting as last observed on-chain, in 1e8 fixed-point
/// units, held BigInt-as-string.
///
/// `deposit` is what went in, `in` how much of it has been swapped, `out` what
/// has been paid out. All optional: `nil` means "never observed", which is not
/// the same as zero.
struct LimitOrderFill: Equatable, Sendable {
    let depositAmount: String?
    let filledInAmount: String?
    let filledOutAmount: String?

    static let unobserved = LimitOrderFill(depositAmount: nil, filledInAmount: nil, filledOutAmount: nil)

    /// The observed `(deposit, in)` pair as exact integers, or `nil` when the
    /// split isn't knowable: never observed, unparseable, negative, or a zero
    /// deposit (dividing by which is a crash, not a percentage).
    ///
    /// Parsed as `BigInt`, never `Decimal`. These are arbitrary-precision
    /// integer strings off the wire (THORChain's accounting is `cosmos.Uint`, a
    /// big.Int), and `Decimal` silently rounds past ~38 significant digits — so
    /// two different amounts could parse equal and report a partially-filled
    /// order as fully filled. `LimitMath` avoids `Decimal` on these same units
    /// for the same reason.
    private var observedSplit: (deposit: BigInt, filled: BigInt)? {
        guard let depositAmount, let filledInAmount,
              let deposit = BigInt(depositAmount),
              let filled = BigInt(filledInAmount),
              deposit > 0, filled >= 0 else {
            return nil
        }
        return (deposit, filled)
    }

    /// How much of the deposit has been swapped so far, as a 0...1 fraction, or
    /// `nil` when it can't be known.
    ///
    /// Derived rather than stored: a persisted percentage could drift out of
    /// sync with the amounts it came from, and there'd be no way to tell which
    /// was right.
    ///
    /// For DISPLAY. The ratio is computed by exact integer division scaled to
    /// `fractionScale`, so the conversion to `Decimal` happens on a bounded
    /// 0...1 value that can't overflow it. Rounding here is display rounding
    /// only — `isPartiallyFilled` never consults it.
    var fillFraction: Decimal? {
        guard let (deposit, filled) = observedSplit else { return nil }
        // An `in` above `deposit` is not something the protocol should produce;
        // clamp rather than report >100% if it ever does.
        guard filled < deposit else { return 1 }
        let scaled = (filled * Self.fractionScale) / deposit
        return Decimal(string: String(scaled)).map { $0 / Decimal(Self.fractionScaleValue) }
    }

    /// True when the order has filled in part but not in full — the remainder is
    /// genuinely still resting.
    ///
    /// This is a QUALIFIER on in-progress, not a status of its own: an order
    /// fills via streaming sub-swaps, so a partial fill is a normal stage of a
    /// live order rather than a distinct outcome. Keeping it out of
    /// `LimitOrderStatus` is what stops the status vocabulary from growing a
    /// case that can contradict the amounts.
    ///
    /// Decided by exact integer comparison, NOT by `fillFraction`: a fill small
    /// enough to round to 0% at display scale is still a partial fill, and the
    /// remainder is still resting.
    var isPartiallyFilled: Bool {
        guard let (deposit, filled) = observedSplit else { return false }
        return filled > 0 && filled < deposit
    }

    /// The unfilled remainder (`deposit - in`) in 1e8 units, or `nil` when the
    /// split isn't knowable. Zero when the order filled completely.
    ///
    /// This is what a terminal order REFUNDS. It is the second leg of an
    /// expiry-after-partial settlement: the protocol pays out `out` in the
    /// target asset AND returns `deposit - in` in the source asset.
    var refundedAmount: BigInt? {
        guard let (deposit, filled) = observedSplit else { return nil }
        guard filled < deposit else { return 0 }
        return deposit - filled
    }

    /// `out` — what has actually been paid out in the TARGET asset, in 1e8
    /// units. `nil` when never observed or unparseable.
    var paidOutAmount: BigInt? {
        guard let filledOutAmount, let out = BigInt(filledOutAmount), out >= 0 else { return nil }
        return out
    }

    /// Fixed-point scale for the display fraction — 6 dp is far finer than any
    /// percentage the UI renders.
    ///
    /// Declared once as an `Int` and widened at each use site, so the integer
    /// scaling and the `Decimal` division that undoes it can never drift apart.
    private static let fractionScaleValue = 1_000_000
    private static let fractionScale = BigInt(fractionScaleValue)
}

// MARK: - Expiry countdown

/// A resting order's expiry, anchored to the last on-chain observation.
///
/// The countdown is NOT derived from the order's stored TTL and creation date:
/// that would be a guess that drifts (and says nothing about a chain whose
/// blocks aren't exactly 6s). `time_to_expiry_blocks` is a live countdown the
/// queue reports on every poll; this interpolates between polls so the chip
/// ticks rather than jumping once a minute.
struct LimitOrderExpiry: Equatable, Sendable {
    /// Blocks remaining as of `observedAt`.
    let blocksRemaining: Int
    let observedAt: Date

    /// THORChain block time. Approximate by nature — the chain targets ~6s but
    /// does not guarantee it, which is precisely why this is re-anchored to a
    /// fresh `blocksRemaining` on every poll rather than run open-loop.
    static let secondsPerBlock: TimeInterval = 6

    /// Seconds left at `now`, floored at zero. Never negative: an elapsed
    /// countdown is "expired", not "-3m".
    func secondsRemaining(now: Date) -> TimeInterval {
        let atObservation = TimeInterval(blocksRemaining) * Self.secondsPerBlock
        let elapsed = now.timeIntervalSince(observedAt)
        return max(0, atObservation - elapsed)
    }

    func hasElapsed(now: Date) -> Bool {
        secondsRemaining(now: now) <= 0
    }
}

// MARK: - Order snapshot

/// Sendable snapshot of a `LimitOrder` for the tx-history surfaces.
struct LimitOrderDetails: Equatable, Sendable, Identifiable {
    let id: String
    /// The order's on-chain identity, and the key the tx-history row joins on.
    let inboundTxHash: String
    let sourceAsset: String
    let targetAsset: String
    /// Price the order executes at, expressed as target-per-source unit.
    let targetPrice: Decimal
    /// TTL the user picked, in THORChain blocks. The fallback for the expiry
    /// chip when the queue has not been polled yet.
    let expiryBlocks: Int
    let createdAt: Date
    let status: LimitOrderStatus
    let minOutputOverride: Decimal?
    let fill: LimitOrderFill
    /// `nil` until the queue has been polled at least once, or once the order
    /// has closed (a terminal order is gone from the queue and has no countdown
    /// left to report).
    let expiry: LimitOrderExpiry?
    /// The exact integers a cancel memo must reproduce (captured at signing),
    /// the chain the order was funded from, and the queue's own trade target for
    /// cross-checking. All optional and all fail closed — see
    /// `limitOrderCancelEligibility`, which is the only thing that should read
    /// them.
    let sourceAmount1e8: String?
    let tradeTarget: String?
    let observedTradeTarget: String?
    let sourceChainRawValue: String?
    /// Set once a cancel has been CONFIRMED broadcast for this order. The order
    /// is deliberately left `.pending` at that point (see `LimitOrder`), so this
    /// is the only thing distinguishing "resting, untouched" from "resting, with
    /// a cancel already on-chain".
    let cancelBroadcastHash: String?

    /// Spelled out rather than left to the memberwise synthesis so the
    /// cancel-related fields can default to `nil` — every existing construction
    /// site describes an order that simply predates cancelling, and defaulting
    /// them keeps "not known" as the thing a caller has to opt OUT of.
    init(
        id: String,
        inboundTxHash: String,
        sourceAsset: String,
        targetAsset: String,
        targetPrice: Decimal,
        expiryBlocks: Int,
        createdAt: Date,
        status: LimitOrderStatus,
        minOutputOverride: Decimal?,
        fill: LimitOrderFill,
        expiry: LimitOrderExpiry?,
        sourceAmount1e8: String? = nil,
        tradeTarget: String? = nil,
        observedTradeTarget: String? = nil,
        sourceChainRawValue: String? = nil,
        cancelBroadcastHash: String? = nil
    ) {
        self.id = id
        self.inboundTxHash = inboundTxHash
        self.sourceAsset = sourceAsset
        self.targetAsset = targetAsset
        self.targetPrice = targetPrice
        self.expiryBlocks = expiryBlocks
        self.createdAt = createdAt
        self.status = status
        self.minOutputOverride = minOutputOverride
        self.fill = fill
        self.expiry = expiry
        self.sourceAmount1e8 = sourceAmount1e8
        self.tradeTarget = tradeTarget
        self.observedTradeTarget = observedTradeTarget
        self.sourceChainRawValue = sourceChainRawValue
        self.cancelBroadcastHash = cancelBroadcastHash
    }

    var fillFraction: Decimal? { fill.fillFraction }

    /// True once the order can no longer fill. Drives the resting-only surfaces
    /// (the live expiry chip; later, the Cancel action).
    var isTerminal: Bool {
        switch status {
        case .pending:
            return false
        case .filled, .refunded, .expired, .cancelled:
            return true
        }
    }

    /// The order COMPLETED. `IsDone` on-chain is `State.In == State.Deposit`, so
    /// this is a statement that nothing was left over — regardless of what the
    /// last snapshot happened to catch.
    private var didFillCompletely: Bool { status == .filled }

    /// Whether to report a partial fill.
    ///
    /// Not simply `fill.isPartiallyFilled`. The stored split is the last
    /// RESTING observation, taken up to a poll interval before the order
    /// closed — an order seen 40% filled and then completing leaves that 40%
    /// behind as the final snapshot. Reading it literally would caption a
    /// completed order "40% filled". `.filled` means it finished; the snapshot
    /// is just stale.
    var isPartiallyFilled: Bool {
        !didFillCompletely && fill.isPartiallyFilled
    }

    /// The order was refunded in part or in whole — an unfilled remainder came
    /// back.
    ///
    /// Guarded twice, and both guards matter:
    /// - not while live: a resting order's unfilled remainder is still working,
    ///   not returned.
    /// - not when `.filled`: same stale-snapshot trap as above, except the
    ///   consequence is worse. A completed order whose last snapshot read 40%
    ///   would claim 60% of the deposit was refunded — money that was never
    ///   sent back, reported as fact, on a screen about the user's own funds.
    var wasRefunded: Bool {
        guard isTerminal, !didFillCompletely, let refunded = fill.refundedAmount else { return false }
        return refunded > 0
    }
}
