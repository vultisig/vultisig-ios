//
//  THORChainTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Midgard Action Status → App Status Mapping
///
/// Canonical mapping (authoritative):
/// - action.status == "success" => AppStatus = SUCCESS (confirmed)
/// - action.status == "pending" => AppStatus = PENDING
/// - action.status == "refund" => AppStatus = FAILED_REFUNDED
///
/// Reason fields (display-only; do not affect canonical mapping):
/// When AppStatus = FAILED_REFUNDED:
/// - Primary failure reason: action.metadata.refund.reason OR action.metadata.failed.reason
/// - Optional reason code: action.metadata.refund.code OR action.metadata.failed.code
/// - Optional memo: action.metadata.failed.memo
/// - Outbound tx(s): action.out[] (typically refund outbounds)
struct THORChainTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                THORChainTransactionStatusAPI.getActions(txHash: query.txHash, chain: query.chain),
                responseType: THORChainActionsResponse.self
            )

            // Check if we have any actions for this txid
            guard let action = response.data.actions.first else {
                // No actions found for this transaction
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Parse block height
            let blockNum = Int(action.height)

            // Canonical mapping based on action.status
            return mapActionToStatus(action: action, blockNumber: blockNum)

        } catch let error as HTTPError {
            return try handleHTTPError(error)
        }
    }

    private func mapActionToStatus(action: MidgardAction, blockNumber: Int?) -> TransactionStatusResult {
        switch action.status.lowercased() {
        case "success":
            // Action completed successfully
            return TransactionStatusResult(
                status: .confirmed,
                blockNumber: blockNumber,
                confirmations: nil
            )

        case "pending":
            // Action is still pending (outbound txs not yet processed)
            return TransactionStatusResult(
                status: .pending,
                blockNumber: blockNumber,
                confirmations: nil
            )

        case "refund":
            // Action was refunded (failed and refunded)
            let failureReason = buildRefundReason(metadata: action.metadata)
            return TransactionStatusResult(
                status: .failed(reason: failureReason),
                blockNumber: blockNumber,
                confirmations: nil
            )

        default:
            // Unknown status - treat as pending
            return TransactionStatusResult(
                status: .pending,
                blockNumber: blockNumber,
                confirmations: nil
            )
        }
    }

    private func buildRefundReason(metadata: MidgardActionMetadata?) -> String {
        var parts: [String] = ["Transaction refunded"]

        // Priority 1: refund.reason
        if let refundReason = metadata?.refund?.reason {
            parts.append("Reason: \(refundReason)")
        } else if let failedReason = metadata?.failed?.reason {
            // Priority 2: failed.reason
            parts.append("Reason: \(failedReason)")
        }

        // Optional code (refund.code OR failed.code)
        if let refundCode = metadata?.refund?.code {
            parts.append("Code: \(refundCode)")
        } else if let failedCode = metadata?.failed?.code {
            parts.append("Code: \(failedCode)")
        }

        // Optional memo
        if let memo = metadata?.failed?.memo, !memo.isEmpty {
            parts.append("Memo: \(memo)")
        }

        return parts.joined(separator: ", ")
    }

    /// Maps HTTP failures to a status.
    /// - 404: Midgard has no action for this txid yet → `.notFound` (keep polling).
    /// - 429 / 5xx: marked `.failed` so the error surfaces to the user.
    /// - timeout / network / other: transport-level, not an on-chain result, so
    ///   thrown — the poller keeps polling and the duplicate-broadcast check keeps
    ///   retrying instead of marking a live tx permanently FAILED.
    private func handleHTTPError(_ error: HTTPError) throws -> TransactionStatusResult {
        if case .statusCode(let code, _) = error {
            if code == 404 {
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            if code == 429 {
                return TransactionStatusResult(
                    status: .failed(reason: "Rate limited - too many requests"),
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            if code >= 500 {
                return TransactionStatusResult(
                    status: .failed(reason: "Server error: \(code)"),
                    blockNumber: nil,
                    confirmations: nil
                )
            }
        }

        throw error
    }
}
