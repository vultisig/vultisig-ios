//
//  TransactionHistoryItem.swift
//  VultisigApp
//

import Foundation
import SwiftData

@Model
final class TransactionHistoryItem {
    var id: UUID
    var txHash: String
    var approveTxHash: String?
    var pubKeyECDSA: String

    // Type & Status stored as raw strings for SwiftData compatibility
    var typeRawValue: String
    var statusRawValue: String

    // Chain
    var chainRawValue: String

    // Snapshotted coin info (survives coin removal)
    var coinTicker: String
    var coinLogo: String
    var coinChainLogo: String?

    // Amounts
    var amountCrypto: String
    var amountFiat: String

    // Addresses
    var fromAddress: String
    var toAddress: String

    // Swap-specific
    var toCoinTicker: String?
    var toCoinLogo: String?
    var toCoinChainLogo: String?
    var toAmountCrypto: String?
    var toAmountFiat: String?
    var swapProvider: String?

    // Fee
    var feeCrypto: String
    var feeFiat: String

    // Network & Explorer
    var network: String
    var explorerLink: String

    // Timestamps
    var createdAt: Date
    var completedAt: Date?

    // Estimated time for in-progress display
    var estimatedTime: String?

    // Error details
    var errorMessage: String?

    // SwapKit `/track` integration — all optional so the migration is
    // additive (no schema bump needed for existing rows).
    /// Aggregator id returned by `/v3/swap`. Analytics + cross-reference only;
    /// not a tracking key.
    var swapKitSwapId: String?
    /// Route id from the prior `/v3/quote` call. Forensic debugging only.
    var swapKitRouteId: String?
    /// The source-chain tx hash SwapKit's `/track` uses as the polling key.
    /// May equal `txHash` for native sends; kept separate so non-EVM source
    /// chains (where the broadcast hash differs from the SwapKit-known hash)
    /// can still poll.
    var swapKitBroadcastHash: String?
    /// `chainId` string passed alongside `broadcastHash` to `/track`. Mirrors
    /// the canonical chain table in `swapkit-spike/api-contract.md`.
    var swapKitSourceChainId: String?
    /// Provider name from the SwapKit response (`CHAINFLIP`, `NEAR`, etc.) —
    /// kept separate from the existing `swapProvider` display string so the
    /// detail screen can match against the wire enum.
    var swapKitProvider: String?
    /// Latest coarse `TxnStatus` string seen on a `/track` response.
    /// `not_started | pending | swapping | completed | refunded | unknown | failed`.
    var swapKitLatestStatus: String?
    /// Latest fine-grained `TrackingStatus` string seen on `/track`.
    /// 14 documented values per `api-contract.md`.
    var swapKitLatestTrackingStatus: String?
    /// Timestamp of the most recent `/track` poll (success or failure). Used
    /// for backoff + resume-from-background scheduling.
    var swapKitLastPolledAt: Date?
    /// Timestamp the first `/track` poll succeeded — used as the start of the
    /// "stuck in unknown" 10-minute window. Set lazily on first poll.
    var swapKitTrackingStartedAt: Date?
    /// `true` once `SwapKitTrackingService` has given up on `/track` (promoted
    /// the row to `unknownPendingExtended` after exhausting retries / the
    /// unknown give-up window). While set, the tx-history viewmodel falls
    /// back to native chain polling so the user still sees source-chain
    /// confirmation. Cleared back to `false` on the next successful `/track`
    /// response so `/track` regains authority.
    var swapKitTrackerOutage: Bool?

    init(
        id: UUID = UUID(),
        txHash: String,
        approveTxHash: String? = nil,
        pubKeyECDSA: String,
        typeRawValue: String,
        statusRawValue: String,
        chainRawValue: String,
        coinTicker: String,
        coinLogo: String,
        coinChainLogo: String? = nil,
        amountCrypto: String,
        amountFiat: String,
        fromAddress: String,
        toAddress: String,
        toCoinTicker: String? = nil,
        toCoinLogo: String? = nil,
        toCoinChainLogo: String? = nil,
        toAmountCrypto: String? = nil,
        toAmountFiat: String? = nil,
        swapProvider: String? = nil,
        feeCrypto: String,
        feeFiat: String,
        network: String,
        explorerLink: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        estimatedTime: String? = nil,
        errorMessage: String? = nil,
        swapKitSwapId: String? = nil,
        swapKitRouteId: String? = nil,
        swapKitBroadcastHash: String? = nil,
        swapKitSourceChainId: String? = nil,
        swapKitProvider: String? = nil,
        swapKitLatestStatus: String? = nil,
        swapKitLatestTrackingStatus: String? = nil,
        swapKitLastPolledAt: Date? = nil,
        swapKitTrackingStartedAt: Date? = nil,
        swapKitTrackerOutage: Bool? = nil
    ) {
        self.id = id
        self.txHash = txHash
        self.approveTxHash = approveTxHash
        self.pubKeyECDSA = pubKeyECDSA
        self.typeRawValue = typeRawValue
        self.statusRawValue = statusRawValue
        self.chainRawValue = chainRawValue
        self.coinTicker = coinTicker
        self.coinLogo = coinLogo
        self.coinChainLogo = coinChainLogo
        self.amountCrypto = amountCrypto
        self.amountFiat = amountFiat
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.toCoinTicker = toCoinTicker
        self.toCoinLogo = toCoinLogo
        self.toCoinChainLogo = toCoinChainLogo
        self.toAmountCrypto = toAmountCrypto
        self.toAmountFiat = toAmountFiat
        self.swapProvider = swapProvider
        self.feeCrypto = feeCrypto
        self.feeFiat = feeFiat
        self.network = network
        self.explorerLink = explorerLink
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.estimatedTime = estimatedTime
        self.errorMessage = errorMessage
        self.swapKitSwapId = swapKitSwapId
        self.swapKitRouteId = swapKitRouteId
        self.swapKitBroadcastHash = swapKitBroadcastHash
        self.swapKitSourceChainId = swapKitSourceChainId
        self.swapKitProvider = swapKitProvider
        self.swapKitLatestStatus = swapKitLatestStatus
        self.swapKitLatestTrackingStatus = swapKitLatestTrackingStatus
        self.swapKitLastPolledAt = swapKitLastPolledAt
        self.swapKitTrackingStartedAt = swapKitTrackingStartedAt
        self.swapKitTrackerOutage = swapKitTrackerOutage
    }
}
