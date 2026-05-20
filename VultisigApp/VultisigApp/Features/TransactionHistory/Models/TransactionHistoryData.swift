//
//  TransactionHistoryData.swift
//  VultisigApp
//

import Foundation

// MARK: - Type Enum

enum TransactionHistoryType: String, Codable, Sendable, Hashable {
    case send
    case swap
    case approve
}

// MARK: - Status Enum

enum TransactionHistoryStatus: String, Codable, Sendable, Hashable {
    case inProgress
    case successful
    case error
}

// MARK: - Sendable Value Type

struct TransactionHistoryData: Sendable, Hashable, Identifiable {
    let id: UUID
    let txHash: String
    let approveTxHash: String?
    let pubKeyECDSA: String
    let type: TransactionHistoryType
    let status: TransactionHistoryStatus
    let chainRawValue: String
    let coinTicker: String
    let coinLogo: String
    let coinChainLogo: String?
    let amountCrypto: String
    let amountFiat: String
    let fromAddress: String
    let toAddress: String
    let toCoinTicker: String?
    let toCoinLogo: String?
    let toCoinChainLogo: String?
    let toAmountCrypto: String?
    let toAmountFiat: String?
    let swapProvider: String?
    let feeCrypto: String
    let feeFiat: String
    let network: String
    let explorerLink: String
    let createdAt: Date
    let completedAt: Date?
    let estimatedTime: String?
    let errorMessage: String?
    let swapKitSwapId: String?
    let swapKitRouteId: String?
    let swapKitBroadcastHash: String?
    let swapKitSourceChainId: String?
    let swapKitProvider: String?
    let swapKitLatestStatus: String?
    let swapKitLatestTrackingStatus: String?
    let swapKitLastPolledAt: Date?
    let swapKitTrackingStartedAt: Date?

    // Explicit memberwise initializer — the SwapKit-tracking fields default
    // to `nil` so call-sites that don't care (the existing recorder paths)
    // can keep their positional arg list unchanged after the schema bump.
    init(
        id: UUID,
        txHash: String,
        approveTxHash: String?,
        pubKeyECDSA: String,
        type: TransactionHistoryType,
        status: TransactionHistoryStatus,
        chainRawValue: String,
        coinTicker: String,
        coinLogo: String,
        coinChainLogo: String?,
        amountCrypto: String,
        amountFiat: String,
        fromAddress: String,
        toAddress: String,
        toCoinTicker: String?,
        toCoinLogo: String?,
        toCoinChainLogo: String?,
        toAmountCrypto: String?,
        toAmountFiat: String?,
        swapProvider: String?,
        feeCrypto: String,
        feeFiat: String,
        network: String,
        explorerLink: String,
        createdAt: Date,
        completedAt: Date?,
        estimatedTime: String?,
        errorMessage: String?,
        swapKitSwapId: String? = nil,
        swapKitRouteId: String? = nil,
        swapKitBroadcastHash: String? = nil,
        swapKitSourceChainId: String? = nil,
        swapKitProvider: String? = nil,
        swapKitLatestStatus: String? = nil,
        swapKitLatestTrackingStatus: String? = nil,
        swapKitLastPolledAt: Date? = nil,
        swapKitTrackingStartedAt: Date? = nil
    ) {
        self.id = id
        self.txHash = txHash
        self.approveTxHash = approveTxHash
        self.pubKeyECDSA = pubKeyECDSA
        self.type = type
        self.status = status
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
    }
}

extension TransactionHistoryData {
    /// True when this row was routed through SwapKit and we have the data we
    /// need to drive a `/track` poll. Used by the tx-history viewmodel to
    /// decide whether to surface the SwapKit status badge / detail screen.
    var isSwapKitRouted: Bool {
        guard type == .swap,
              let hash = swapKitBroadcastHash, !hash.isEmpty,
              let chainId = swapKitSourceChainId, !chainId.isEmpty else {
            return false
        }
        return true
    }

    /// The iOS UI state, derived from whatever `/track` data has been
    /// persisted. Falls back to `pending` when no poll has been recorded yet.
    var swapKitUiStatus: SwapKitUiStatus {
        SwapKitTrackingStatusMapper.map(trackingStatus: swapKitLatestTrackingStatus)
    }

    /// SwapKit's public block-explorer deep link. Always available as a
    /// fallback regardless of whether polling is currently active.
    var swapKitTrackerURL: URL? {
        guard let hash = swapKitBroadcastHash, !hash.isEmpty else { return nil }
        return URL(string: "https://track.swapkit.dev/?hash=\(hash)")
    }
}

// MARK: - Conversions

extension TransactionHistoryData {

    @MainActor
    init(item: TransactionHistoryItem) {
        self.id = item.id
        self.txHash = item.txHash
        self.approveTxHash = item.approveTxHash
        self.pubKeyECDSA = item.pubKeyECDSA
        self.type = TransactionHistoryType(rawValue: item.typeRawValue) ?? .send
        self.status = TransactionHistoryStatus(rawValue: item.statusRawValue) ?? .inProgress
        self.chainRawValue = item.chainRawValue
        self.coinTicker = item.coinTicker
        self.coinLogo = item.coinLogo
        self.coinChainLogo = item.coinChainLogo
        self.amountCrypto = item.amountCrypto
        self.amountFiat = item.amountFiat
        self.fromAddress = item.fromAddress
        self.toAddress = item.toAddress
        self.toCoinTicker = item.toCoinTicker
        self.toCoinLogo = item.toCoinLogo
        self.toCoinChainLogo = item.toCoinChainLogo
        self.toAmountCrypto = item.toAmountCrypto
        self.toAmountFiat = item.toAmountFiat
        self.swapProvider = item.swapProvider
        self.feeCrypto = item.feeCrypto
        self.feeFiat = item.feeFiat
        self.network = item.network
        self.explorerLink = item.explorerLink
        self.createdAt = item.createdAt
        self.completedAt = item.completedAt
        self.estimatedTime = item.estimatedTime
        self.errorMessage = item.errorMessage
        self.swapKitSwapId = item.swapKitSwapId
        self.swapKitRouteId = item.swapKitRouteId
        self.swapKitBroadcastHash = item.swapKitBroadcastHash
        self.swapKitSourceChainId = item.swapKitSourceChainId
        self.swapKitProvider = item.swapKitProvider
        self.swapKitLatestStatus = item.swapKitLatestStatus
        self.swapKitLatestTrackingStatus = item.swapKitLatestTrackingStatus
        self.swapKitLastPolledAt = item.swapKitLastPolledAt
        self.swapKitTrackingStartedAt = item.swapKitTrackingStartedAt
    }

    func toItem() -> TransactionHistoryItem {
        TransactionHistoryItem(
            id: id,
            txHash: txHash,
            approveTxHash: approveTxHash,
            pubKeyECDSA: pubKeyECDSA,
            typeRawValue: type.rawValue,
            statusRawValue: status.rawValue,
            chainRawValue: chainRawValue,
            coinTicker: coinTicker,
            coinLogo: coinLogo,
            coinChainLogo: coinChainLogo,
            amountCrypto: amountCrypto,
            amountFiat: amountFiat,
            fromAddress: fromAddress,
            toAddress: toAddress,
            toCoinTicker: toCoinTicker,
            toCoinLogo: toCoinLogo,
            toCoinChainLogo: toCoinChainLogo,
            toAmountCrypto: toAmountCrypto,
            toAmountFiat: toAmountFiat,
            swapProvider: swapProvider,
            feeCrypto: feeCrypto,
            feeFiat: feeFiat,
            network: network,
            explorerLink: explorerLink,
            createdAt: createdAt,
            completedAt: completedAt,
            estimatedTime: estimatedTime,
            errorMessage: errorMessage,
            swapKitSwapId: swapKitSwapId,
            swapKitRouteId: swapKitRouteId,
            swapKitBroadcastHash: swapKitBroadcastHash,
            swapKitSourceChainId: swapKitSourceChainId,
            swapKitProvider: swapKitProvider,
            swapKitLatestStatus: swapKitLatestStatus,
            swapKitLatestTrackingStatus: swapKitLatestTrackingStatus,
            swapKitLastPolledAt: swapKitLastPolledAt,
            swapKitTrackingStartedAt: swapKitTrackingStartedAt
        )
    }
}
