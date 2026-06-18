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
        expiryHours: Int = 0
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
    }
}
