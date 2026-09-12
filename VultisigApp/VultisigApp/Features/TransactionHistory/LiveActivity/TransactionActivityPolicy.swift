import CryptoKit
import Foundation

enum TransactionActivityPolicy {
    static let ledgerKey = "transactionLiveActivitiesLedgerV1"
    static let maximumActivities = 2
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
        guard !payload.skipBroadcast, !payload.chainSpecific.sendsMaxAmount, !payload.isQbtcClaim, payload.qbtcClaimPayload == nil,
              payload.solanaStakingPayload == nil, payload.kaminoPayload == nil,
              payload.dappMetadata == nil,
              !isLimitSwapMemo(payload.memo), !isModifyLimitSwapMemo(payload.memo) else { return false }
        if let swap = payload.swapPayload {
            switch swap {
            case .swapkit: return true
            case .generic(let generic): return generic.provider == .swapkit
            default: return false
            }
        }
        guard payload.approvePayload == nil, payload.signData == nil,
              payload.wasmExecuteContractPayload == nil,
              payload.tronTriggerSmartContractPayload == nil,
              !RippleTrustSetPresentation.isTrustSet(payload: payload) else { return false }
        let operation = SignedTransactionDecoder.decode(payload).operation
        if operation == .transfer { return true }
        // Existing signed-content readers do not cover EVM/UTXO plain sends.
        // An empty memo and no raw signing/contract payload means the wallet's
        // standard native/token-transfer builder owns the transaction shape.
        return operation == .unknown && (payload.memo ?? "").isEmpty
            && (payload.coin.chainType == .EVM || payload.coin.chainType == .UTXO)
    }

    static func phase(for row: TransactionHistoryData) -> TransactionActivityState.Phase {
        if row.type == .swap {
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
                if row.swapTracking == nil, row.status == .error,
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
        guard row.type == .swap else { return false }
        if row.swapTracking?.trackerOutage == true { return true }
        let fine = row.swapTracking?.latestTrackingStatus?.lowercased()
        guard let raw = fine?.isEmpty == false ? fine : row.swapTracking?.latestStatus?.lowercased() else { return false }
        return !["not_started", "starting", "broadcasted", "mempool", "inbound", "outbound",
                 "pending", "swapping", "completed", "refunded", "partially_refunded", "reverted", "failed"].contains(raw)
    }

    static func state(for row: TransactionHistoryData, phase: TransactionActivityState.Phase,
                      observedAt: Date, revision: Int, delayed: Bool, showDetails: Bool) -> TransactionActivityState {
        let summary = row.type == .swap
            ? "\(row.amountCrypto) → \(row.toCoinTicker ?? "")" : row.amountCrypto
        return TransactionActivityState(
            phase: phase, observedAt: observedAt, revision: revision, updateDelayed: delayed,
            summary: summary, network: row.network, showDetails: showDetails,
            operation: row.type == .swap ? .swap : .send,
            recipient: row.type == .send ? row.toAddress : nil,
            fee: row.feeCrypto.isEmpty ? nil : row.feeCrypto,
            provider: row.type == .swap ? row.swapProvider : nil, submittedAt: row.createdAt,
            sourceAssetID: row.coinLogo, destinationAssetID: row.type == .swap ? row.toCoinLogo : nil
        )
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
