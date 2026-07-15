//
//  LimitOrder.swift
//  VultisigApp
//

import BigInt
import Foundation
import SwiftData

@MainActor
@Model
final class LimitOrder {

    @Attribute(.unique) var id: String

    var inboundTxHash: String
    var sourceAsset: String
    /// BigInt-as-string for cross-platform / future-proofing — `BigInt` is not
    /// a native SwiftData primitive.
    var sourceAmount: String
    var sourceDecimals: Int
    var targetAsset: String
    var destAddress: String
    var targetPrice: Decimal
    var expiryBlocks: Int
    var createdAt: Date
    var statusRawValue: String
    /// Effective guaranteed-minimum output the order was actually signed with,
    /// when the memo's LIM had to be rounded UP to fit the source-chain byte
    /// budget. `nil` means the LIM matches the exact `targetPrice`-derived
    /// value. Persisted because it is the figure shown on Verify — the order
    /// card has to keep showing what the user signed, not a recomputed guess.
    ///
    /// Optional, so this rides SwiftData lightweight migration.
    var minOutputOverride: Decimal?

    /// The order's fill accounting as last observed on-chain, in 1e8
    /// fixed-point units, stored BigInt-as-string like `sourceAmount`.
    ///
    /// These have to be persisted rather than read live: a terminal order
    /// DISAPPEARS from the queue, taking its fill state with it. Without a
    /// stored copy, an order that expired 40% filled could never say so again —
    /// and that split is exactly what the user needs to understand a two-leg
    /// settlement (part paid out in the target asset, the remainder refunded).
    ///
    /// `deposit` is what went in, `in` how much of it has been swapped, `out`
    /// what has been paid out. All optional: `nil` means "never observed", which
    /// is not the same as zero.
    var depositAmount: String?
    var filledInAmount: String?
    var filledOutAmount: String?

    @Relationship(inverse: \Vault.limitOrders) var vault: Vault?

    init(
        id: String,
        inboundTxHash: String,
        sourceAsset: String,
        sourceAmount: String,
        sourceDecimals: Int,
        targetAsset: String,
        destAddress: String,
        targetPrice: Decimal,
        expiryBlocks: Int,
        createdAt: Date,
        status: LimitOrderStatus,
        minOutputOverride: Decimal? = nil,
        vault: Vault
    ) {
        self.id = id
        self.inboundTxHash = inboundTxHash
        self.sourceAsset = sourceAsset
        self.sourceAmount = sourceAmount
        self.sourceDecimals = sourceDecimals
        self.targetAsset = targetAsset
        self.destAddress = destAddress
        self.targetPrice = targetPrice
        self.expiryBlocks = expiryBlocks
        self.createdAt = createdAt
        self.statusRawValue = status.rawValue
        self.minOutputOverride = minOutputOverride
        self.vault = vault
    }

    var status: LimitOrderStatus {
        LimitOrderStatus(rawValue: statusRawValue) ?? .pending
    }

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
        return Decimal(string: String(scaled)).map { $0 / Decimal(string: String(Self.fractionScale))! }
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

    /// Fixed-point scale for the display fraction — 6 dp is far finer than any
    /// percentage the UI renders.
    private static let fractionScale = BigInt(1_000_000)
}

enum LimitOrderStatus: String, Codable, Equatable {
    case pending
    case filled
    /// The order closed and the funds came back — the observable fact.
    ///
    /// Distinct from `expired`, which is a claim about WHY: an order rejected at
    /// placement (halted pool, bad memo) also refunds, seconds in, with no TTL
    /// elapsed. Nothing reachable from a client distinguishes them — the close
    /// reason lives in an EndBlock event no REST route exposes, and a closed
    /// order is already gone from the queue with its expiry countdown. So the
    /// tracker records this, and doesn't invent the cause.
    case refunded
    /// The order's TTL elapsed. Only for a caller that can actually corroborate
    /// expiry — the tracker cannot, and uses `refunded`.
    case expired
    case cancelled
}

/// Sendable value-type record used as input to `LimitOrderStorageService.persist`.
/// Materialized into a `LimitOrder` (`@Model`) on `@MainActor`.
/// `Hashable` so it can ride along through `SwapRoute` cases without indirection.
struct LimitOrderRecord: Hashable, Sendable {
    let inboundTxHash: String
    let sourceAsset: String
    let sourceAmount: String
    let sourceDecimals: Int
    let targetAsset: String
    let destAddress: String
    let targetPrice: Decimal
    let expiryBlocks: Int
    let createdAt: Date
    let status: LimitOrderStatus
    /// THORChain limit-swap memo (`=<:...`). Carried through the shared
    /// Swap pipeline so the verify screen can rebuild the `KeysignPayload`
    /// without re-running the memo builder. Empty string for legacy
    /// records (`LimitOrder` table doesn't persist this — it's already
    /// implied by `sourceAsset/targetAsset/destAddress/targetPrice`).
    let memo: String
    /// Expiry duration the user originally picked (12 / 24 / 72 hours).
    /// `expiryBlocks` is the THORChain-block expression used in the memo;
    /// `expiryHours` is the human-readable display value the verify and
    /// done screens render alongside the target price.
    let expiryHours: Int
    /// Effective guaranteed-minimum output (target natural units) when the memo's
    /// LIM was rounded UP to fit the source-chain byte budget
    /// (`buildFittedLimitSwapMemo`). `nil` means the LIM equals the exact
    /// `targetPrice`-derived value, so the display falls back to
    /// `limitOrderExpectedOutput`. When set, the Verify/Done "min payout" shows
    /// the EXACT figure the order was signed with (what you see is what you sign).
    let minOutputOverride: Decimal?

    init(
        inboundTxHash: String,
        sourceAsset: String,
        sourceAmount: String,
        sourceDecimals: Int,
        targetAsset: String,
        destAddress: String,
        targetPrice: Decimal,
        expiryBlocks: Int,
        createdAt: Date = Date(),
        status: LimitOrderStatus = .pending,
        memo: String = "",
        expiryHours: Int = 0,
        minOutputOverride: Decimal? = nil
    ) {
        self.inboundTxHash = inboundTxHash
        self.sourceAsset = sourceAsset
        self.sourceAmount = sourceAmount
        self.sourceDecimals = sourceDecimals
        self.targetAsset = targetAsset
        self.destAddress = destAddress
        self.targetPrice = targetPrice
        self.expiryBlocks = expiryBlocks
        self.createdAt = createdAt
        self.status = status
        self.memo = memo
        self.expiryHours = expiryHours
        self.minOutputOverride = minOutputOverride
    }

    /// Returns a copy with the inbound TX hash spliced in. The record is built
    /// at sign time, before the hash exists; the done screen fills it in once
    /// the broadcast returns, then hands it to `LimitOrderStorageService`.
    ///
    /// Every other field must ride along verbatim — this sits on the path the
    /// execution tracker reads back, so a silently dropped field here becomes a
    /// wrong number on the order card.
    func with(inboundTxHash: String) -> LimitOrderRecord {
        LimitOrderRecord(
            inboundTxHash: inboundTxHash,
            sourceAsset: sourceAsset,
            sourceAmount: sourceAmount,
            sourceDecimals: sourceDecimals,
            targetAsset: targetAsset,
            destAddress: destAddress,
            targetPrice: targetPrice,
            expiryBlocks: expiryBlocks,
            createdAt: createdAt,
            status: status,
            memo: memo,
            expiryHours: expiryHours,
            minOutputOverride: minOutputOverride
        )
    }
}
