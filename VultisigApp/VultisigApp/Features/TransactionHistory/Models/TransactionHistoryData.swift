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
    /// Aggregator-agnostic tracking state. `nil` when the row isn't routed
    /// through any tracked provider. `providerKind` selects which
    /// `SwapTrackingService` conformer owns polling.
    let swapTracking: SwapTrackingMetadataData?

    // Explicit memberwise initializer — `swapTracking` defaults to `nil` so
    // existing call sites that don't care (the recorder paths) can omit it.
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
        swapTracking: SwapTrackingMetadataData? = nil
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
        self.swapTracking = swapTracking
    }
}

extension TransactionHistoryData {
    /// True when this row was routed through a swap aggregator with a
    /// registered tracking service. Provider-agnostic — the registry
    /// resolves the actual conformer from `swapTracking.providerKind`.
    var isSwapRouted: Bool {
        swapTracking != nil
    }

    /// The iOS UI state, derived from whatever tracking data has been
    /// persisted.
    ///
    /// Dispatches on `providerKind`, because the same stored string means
    /// different things per provider: a limit order's statuses come from
    /// `LimitOrderStatus` and include states SwapKit has no word for (resting,
    /// expired). Routing every row through SwapKit's table would silently
    /// mistranslate them — an unrecognised value falls through to `pending`
    /// there, so a resting order and an expired one would render identically.
    ///
    /// Each provider's mapper owns its own fallback.
    var swapTrackingUiStatus: SwapTrackingUiStatus {
        let latest = swapTracking?.latestTrackingStatus
        switch swapTracking?.providerKind {
        case THORChainLimitTrackingService.providerKind:
            return THORChainLimitTrackingStatusMapper.map(trackingStatus: latest)
        default:
            return SwapKitTrackingStatusMapper.map(trackingStatus: latest)
        }
    }

    /// SwapKit's public block-explorer deep link. Only available for rows
    /// routed through SwapKit (the detail-sheet button checks for this
    /// specifically). Future providers add their own deep-link helpers.
    var swapKitTrackerURL: URL? {
        guard let tracking = swapTracking,
              tracking.providerKind == SwapKitTrackingService.providerKind,
              let hash = tracking.broadcastHash, !hash.isEmpty else {
            return nil
        }
        // Append the SwapKit chainId so the tracker resolves the hash on the
        // right chain; fall back to hash-only for chains it doesn't map.
        let base = "https://track.swapkit.dev/?hash=\(hash)"
        guard let chain = Chain(rawValue: chainRawValue),
              let chainId = SwapKitChainIdentifier.chainId(for: chain) else {
            return URL(string: base)
        }
        return URL(string: "\(base)&chainId=\(chainId)")
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
        self.swapTracking = item.swapTracking.map { SwapTrackingMetadataData(model: $0) }
    }

    @MainActor
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
            swapTracking: swapTracking?.toModel()
        )
    }
}
