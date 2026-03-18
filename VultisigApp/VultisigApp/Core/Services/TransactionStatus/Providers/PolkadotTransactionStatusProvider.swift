//
//  PolkadotTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Polkadot Transaction Status Logic:
/// - Uses Subscan API for AssetHub Polkadot transaction status checking
/// - Endpoint: https://assethub-polkadot.api.subscan.io/api/scan/extrinsic
/// - Gets detailed status including success/failure from indexed data
/// - Checks `pending` field before `success` to properly detect pending transactions
struct PolkadotTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        let response = try await httpClient.request(
            PolkadotTransactionStatusAPI.getExtrinsicByHash(extrinsicHash: query.txHash),
            responseType: PolkadotTransactionStatusResponse.self
        )

        return processResponse(response: response.data)
    }

    /// Process Subscan API response
    private func processResponse(response: PolkadotTransactionStatusResponse) -> TransactionStatusResult {
        // Check API response code
        if response.code != 0 {
            // Non-zero code means transaction not found in Subscan
            return TransactionStatusResult(
                status: .notFound,
                blockNumber: nil,
                confirmations: nil
            )
        }

        // Check if extrinsic data exists
        guard let extrinsicData = response.data else {
            // code: 0 with data: null means transaction not indexed yet (pending)
            return TransactionStatusResult(
                status: .pending,
                blockNumber: nil,
                confirmations: nil
            )
        }

        let blockNumber = extrinsicData.block_num

        // CRITICAL: Check pending field first!
        // pending=true means transaction is still being processed
        if let pending = extrinsicData.pending, pending {
            return TransactionStatusResult(
                status: .pending,
                blockNumber: blockNumber,
                confirmations: nil
            )
        }

        // Check if extrinsic is finalized (secondary check)
        if let finalized = extrinsicData.finalized, !finalized {
            return TransactionStatusResult(
                status: .pending,
                blockNumber: blockNumber,
                confirmations: nil
            )
        }

        // Now check success/failure (only after confirming it's not pending)
        if extrinsicData.success {
            return TransactionStatusResult(
                status: .confirmed,
                blockNumber: blockNumber,
                confirmations: nil
            )
        } else {
            // Only treat as failed if error exists or explicitly not pending
            let failureReason = buildFailureReason(error: extrinsicData.error)
            return TransactionStatusResult(
                status: .failed(reason: failureReason),
                blockNumber: blockNumber,
                confirmations: nil
            )
        }
    }

    private func buildFailureReason(error: PolkadotTransactionStatusResponse.PolkadotExtrinsicError?) -> String {
        guard let error = error else {
            return "Transaction failed"
        }

        var reason = ""
        if let module = error.module {
            reason += module
        }
        if let name = error.name {
            if !reason.isEmpty {
                reason += "."
            }
            reason += name
        }

        if let doc = error.doc, !doc.isEmpty {
            let docString = doc.joined(separator: " ")
            if !reason.isEmpty {
                reason += ": "
            }
            reason += docString
        }

        return reason.isEmpty ? "Transaction failed" : reason
    }
}
