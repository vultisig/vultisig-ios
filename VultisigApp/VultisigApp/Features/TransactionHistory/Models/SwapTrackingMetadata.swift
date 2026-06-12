//
//  SwapTrackingMetadata.swift
//  VultisigApp
//
//  Per-row swap-aggregator tracking state. Lives in its own SwiftData
//  `@Model` so that adding future providers (a dedicated Chainflip
//  integration, additional THORChain extensions, alternate API providers)
//  doesn't keep growing `TransactionHistoryItem` with provider-specific
//  columns. `providerKind` discriminates which `SwapTrackingService`
//  conformer owns the row.
//

import Foundation
import SwiftData

@Model
final class SwapTrackingMetadata {
    /// Discriminator matching `SwapTrackingService.providerKind`. Today
    /// only "swapKit" is registered. Future providers append entries.
    var providerKind: String

    /// Provider-side swap identifier. SwapKit's `swapId`; other providers'
    /// equivalent of "the thing we POST to /track".
    var swapId: String?

    /// Provider-side route identifier. SwapKit's `routeId`; for providers
    /// without a separate quote/build split, this may equal `swapId`.
    var routeId: String?

    /// On-chain source-tx hash the provider's tracker keys off. Distinct
    /// from the parent row's `txHash` only when the provider broadcasts a
    /// different hash to the inbound chain (rare).
    var broadcastHash: String?

    /// Provider-specific source chain identifier as the tracker expects
    /// it (e.g. SwapKit's chainId — "1" for ETH, "solana" for Solana).
    var sourceChainId: String?

    /// Sub-provider attribution surfaced on the row ("via NEAR", "via
    /// CHAINFLIP", "via ONEINCH"). The provider that actually ran the swap.
    var subProvider: String?

    /// Last raw coarse status string from the provider's tracker. Persisted
    /// so the UI can show "Latest: <status>" without re-polling.
    var latestStatus: String?

    /// Last raw fine-grained status string. SwapKit's `trackingStatus`;
    /// the high-resolution sibling of `latestStatus`.
    var latestTrackingStatus: String?

    /// Wall-clock timestamp of the last successful poll.
    var lastPolledAt: Date?

    /// Wall-clock timestamp of the first poll. Used to compute "extended
    /// unknown" sentinels and tracker-outage thresholds.
    var trackingStartedAt: Date?

    /// `true` when the provider's tracker has been unreachable long enough
    /// that the tx-history viewmodel may fall back to native chain polling
    /// for the row.
    var trackerOutage: Bool?

    init(
        providerKind: String,
        swapId: String? = nil,
        routeId: String? = nil,
        broadcastHash: String? = nil,
        sourceChainId: String? = nil,
        subProvider: String? = nil,
        latestStatus: String? = nil,
        latestTrackingStatus: String? = nil,
        lastPolledAt: Date? = nil,
        trackingStartedAt: Date? = nil,
        trackerOutage: Bool? = nil
    ) {
        self.providerKind = providerKind
        self.swapId = swapId
        self.routeId = routeId
        self.broadcastHash = broadcastHash
        self.sourceChainId = sourceChainId
        self.subProvider = subProvider
        self.latestStatus = latestStatus
        self.latestTrackingStatus = latestTrackingStatus
        self.lastPolledAt = lastPolledAt
        self.trackingStartedAt = trackingStartedAt
        self.trackerOutage = trackerOutage
    }
}

// MARK: - Sendable value-type mirror

/// Sendable, value-type mirror of `SwapTrackingMetadata`. Used by
/// `TransactionHistoryData` so the SwiftData `@Model` doesn't leak across
/// actor boundaries. Stays in lock-step with the `@Model` schema.
struct SwapTrackingMetadataData: Sendable, Hashable {
    let providerKind: String
    let swapId: String?
    let routeId: String?
    let broadcastHash: String?
    let sourceChainId: String?
    let subProvider: String?
    let latestStatus: String?
    let latestTrackingStatus: String?
    let lastPolledAt: Date?
    let trackingStartedAt: Date?
    let trackerOutage: Bool?

    init(
        providerKind: String,
        swapId: String? = nil,
        routeId: String? = nil,
        broadcastHash: String? = nil,
        sourceChainId: String? = nil,
        subProvider: String? = nil,
        latestStatus: String? = nil,
        latestTrackingStatus: String? = nil,
        lastPolledAt: Date? = nil,
        trackingStartedAt: Date? = nil,
        trackerOutage: Bool? = nil
    ) {
        self.providerKind = providerKind
        self.swapId = swapId
        self.routeId = routeId
        self.broadcastHash = broadcastHash
        self.sourceChainId = sourceChainId
        self.subProvider = subProvider
        self.latestStatus = latestStatus
        self.latestTrackingStatus = latestTrackingStatus
        self.lastPolledAt = lastPolledAt
        self.trackingStartedAt = trackingStartedAt
        self.trackerOutage = trackerOutage
    }
}

extension SwapTrackingMetadataData {
    @MainActor
    init(model: SwapTrackingMetadata) {
        self.providerKind = model.providerKind
        self.swapId = model.swapId
        self.routeId = model.routeId
        self.broadcastHash = model.broadcastHash
        self.sourceChainId = model.sourceChainId
        self.subProvider = model.subProvider
        self.latestStatus = model.latestStatus
        self.latestTrackingStatus = model.latestTrackingStatus
        self.lastPolledAt = model.lastPolledAt
        self.trackingStartedAt = model.trackingStartedAt
        self.trackerOutage = model.trackerOutage
    }

    @MainActor
    func toModel() -> SwapTrackingMetadata {
        SwapTrackingMetadata(
            providerKind: providerKind,
            swapId: swapId,
            routeId: routeId,
            broadcastHash: broadcastHash,
            sourceChainId: sourceChainId,
            subProvider: subProvider,
            latestStatus: latestStatus,
            latestTrackingStatus: latestTrackingStatus,
            lastPolledAt: lastPolledAt,
            trackingStartedAt: trackingStartedAt,
            trackerOutage: trackerOutage
        )
    }
}
