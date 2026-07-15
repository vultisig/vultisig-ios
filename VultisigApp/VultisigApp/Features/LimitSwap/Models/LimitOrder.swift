//
//  LimitOrder.swift
//  VultisigApp
//

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

    /// Blocks left before expiry, as the queue last reported them, and WHEN it
    /// reported them.
    ///
    /// Both are needed together: `timeToExpiryBlocks` alone is a number with no
    /// meaning once a minute has passed. Anchoring it to the observation time
    /// is what lets the expiry chip tick live between polls instead of showing
    /// a stale figure — and it's why the chip is honest in a way the stored
    /// TTL + `createdAt` never could be, since that pair assumes the deposit
    /// was queued the instant it was signed and that blocks are exactly 6s.
    ///
    /// `nil` until the first poll. Left alone once an order goes terminal: it
    /// disappears from the queue, and a countdown for a closed order is
    /// meaningless anyway.
    ///
    /// Optional, so these ride SwiftData lightweight migration.
    var timeToExpiryBlocks: Int?
    var expiryObservedAt: Date?

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

    /// The fill accounting as a pure value. The arithmetic lives on
    /// `LimitOrderFill` so the order card and the detail sheet — which read a
    /// `LimitOrderDetails` snapshot, never this `@Model` — derive percentages
    /// and refunds from exactly the same code this does.
    var fill: LimitOrderFill {
        LimitOrderFill(
            depositAmount: depositAmount,
            filledInAmount: filledInAmount,
            filledOutAmount: filledOutAmount
        )
    }

    var fillFraction: Decimal? { fill.fillFraction }

    var isPartiallyFilled: Bool { fill.isPartiallyFilled }

    /// The live expiry countdown, or `nil` if the queue has never been polled
    /// for this order.
    var expiry: LimitOrderExpiry? {
        guard let timeToExpiryBlocks, let expiryObservedAt else { return nil }
        return LimitOrderExpiry(blocksRemaining: timeToExpiryBlocks, observedAt: expiryObservedAt)
    }

    /// Sendable snapshot for the tx-history surfaces.
    var details: LimitOrderDetails {
        LimitOrderDetails(
            id: id,
            inboundTxHash: inboundTxHash,
            sourceAsset: sourceAsset,
            targetAsset: targetAsset,
            targetPrice: targetPrice,
            expiryBlocks: expiryBlocks,
            createdAt: createdAt,
            status: status,
            minOutputOverride: minOutputOverride,
            fill: fill,
            expiry: expiry
        )
    }
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
