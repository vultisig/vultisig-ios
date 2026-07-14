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
}

enum LimitOrderStatus: String, Codable, Equatable {
    case pending
    case filled
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
