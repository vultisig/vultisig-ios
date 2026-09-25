import CryptoKit
import Foundation
import VultisigUIResources

enum TransactionActivityPolicy {
    static let nativeSourceProviderKind = "nativeSource"
    static let ledgerKey = "transactionLiveActivitiesLedgerV1"
    static let maximumAge: TimeInterval = 7.5 * 60 * 60

    static var isSupportedPlatform: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// Only the app stores this digest. ActivityKit receives the random record UUID.
    static func identity(_ row: TransactionHistoryData) -> String {
        let parts = [row.pubKeyECDSA, row.chainRawValue, row.txHash]
        let encoded = parts.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(encoded.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isEligible(_ payload: KeysignPayload) -> Bool {
        // Admission is called only after positive broadcast evidence. Signing-only
        // payloads cannot produce a receipt; every submitted operation can.
        !payload.skipBroadcast
    }

    static func usesNativeStatus(_ row: TransactionHistoryData) -> Bool {
        row.swapTracking == nil || row.swapTracking?.providerKind == nativeSourceProviderKind
    }

    static func phase(for row: TransactionHistoryData) -> TransactionActivityState.Phase {
        if row.type == .limit {
            switch row.swapTracking?.latestStatus?.lowercased() {
            case "filled": return .filled
            case "refunded": return .refunded
            case "cancelled": return .cancelled
            case "expired": return .expired
            default: return .pending
            }
        }
        if row.type == .swap {
            if row.swapTracking?.providerKind == nativeSourceProviderKind, row.status == .successful {
                // Only known same-chain routes settle atomically with this tx.
                // Other routes finish observing the broadcast source explicitly.
                return row.swapTracking?.subProvider == "atomic" ? .completed : .sourceConfirmedOnly
            }
            // A native fallback updates the coarse row, but never proves swap settlement.
            let fine = row.swapTracking?.latestTrackingStatus?.lowercased()
            let raw = fine?.isEmpty == false ? fine : row.swapTracking?.latestStatus?.lowercased()
            switch raw {
            case "completed": return .completed
            case "refunded": return .refunded
            case "partially_refunded": return .partiallyRefunded
            case "reverted", "failed": return .failed
            case "outbound", "swapping": return .swapping
            default:
                // Without provider metadata, a durable coarse failure came from
                // native tracking. Provider operational errors remain ambiguous.
                if usesNativeStatus(row), row.status == .error,
                   !TransactionHistoryLegacyTimeout.localizedMessages().contains(row.errorMessage ?? "") {
                    return .failed
                }
                return row.status == .successful ? .sourceConfirmed : .pending
            }
        }
        switch row.status {
        case .successful: return .confirmed
        case .error:
            if TransactionHistoryLegacyTimeout.localizedMessages().contains(row.errorMessage ?? "") { return .pending }
            return .failed
        case .inProgress: return .pending
        }
    }

    static func providerIsDelayed(_ row: TransactionHistoryData) -> Bool {
        if row.type == .limit { return row.swapTracking?.trackerOutage == true }
        guard row.type == .swap else { return false }
        if row.swapTracking?.trackerOutage == true { return true }
        let fine = row.swapTracking?.latestTrackingStatus?.lowercased()
        guard let raw = fine?.isEmpty == false ? fine : row.swapTracking?.latestStatus?.lowercased() else { return false }
        return !["not_started", "starting", "broadcasted", "mempool", "inbound", "outbound",
                 "pending", "swapping", "completed", "refunded", "partially_refunded", "reverted", "failed"].contains(raw)
    }

    static func operation(for type: TransactionHistoryType) -> TransactionActivityState.Operation {
        switch type {
        case .send: .send
        case .swap: .swap
        case .limit: .limit
        case .approve: .approval
        case .trustLineActivation, .transaction: .transaction
        }
    }

    static func state(for row: TransactionHistoryData, phase: TransactionActivityState.Phase,
                      observedAt: Date, revision: Int, delayed: Bool, showDetails: Bool,
                      preparedImageKey: (String) -> String? = { _ in nil }) -> TransactionActivityState {
        let destinationLogo = destinationLogo(for: row)
        let hasDestination = row.toCoinTicker?.isEmpty == false
        let summary = (row.type == .swap || row.type == .limit) && hasDestination
            ? "\(row.amountCrypto) → \(row.toCoinTicker ?? "")" : row.amountCrypto
        return TransactionActivityState(
            phase: phase, observedAt: observedAt, revision: revision, updateDelayed: delayed,
            summary: summary.isEmpty ? row.coinTicker : summary, network: row.network, showDetails: showDetails,
            operation: operation(for: row.type),
            recipient: row.type == .send ? row.toAddress : nil,
            fee: row.feeCrypto.isEmpty ? nil : row.feeCrypto,
            provider: row.type == .swap ? row.swapProvider : nil, submittedAt: row.createdAt,
            sourceAssetID: row.coinLogo, destinationAssetID: destinationLogo,
            sourceImageKey: showDetails ? preparedImageKey(row.coinLogo) : nil,
            destinationImageKey: showDetails ? destinationLogo.flatMap(preparedImageKey) : nil,
            sourceSummary: row.amountCrypto.isEmpty ? row.coinTicker : row.amountCrypto,
            destinationTicker: (row.type == .swap || row.type == .limit) && hasDestination ? row.toCoinTicker : nil,
            staleWindow: TransactionActivityStaleness.window(for: row)
        )
    }

    static func destinationLogo(for row: TransactionHistoryData) -> String? {
        row.type == .swap || row.type == .limit ? row.toCoinLogo : nil
    }

    static func remoteImageURLs(for row: TransactionHistoryData) -> [URL] {
        var urls: [URL] = []
        for logo in [row.coinLogo, destinationLogo(for: row)].compactMap({ $0 }) {
            guard let url = URL(string: logo), RemoteImageCache.key(for: url) != nil,
                  !urls.contains(url) else { continue }
            urls.append(url)
        }
        return urls
    }

}

/// Value events are emitted only after successful saves, never from a view's appearance.
enum TransactionHistoryActivityEvent {
    case saved(TransactionHistoryData)
    case nativeStatus(TransactionHistoryData, Date)
    case nativePending(TransactionHistoryData, Date)
    case swapStatus(TransactionHistoryData, Date)
    case delayed(TransactionHistoryData)
    case deleted

    static let notification = Notification.Name("TransactionHistoryActivityEvent")
}
