//
//  PolkadotTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Polkadot Transaction Status Logic:
/// - Uses Subscan API for transaction status checking
/// - Currently: https://polkadot.api.subscan.io/api/scan/extrinsic (public API)
/// - TODO: Switch to Vultisig proxy once ready: https://api.vultisig.com/dot/api/scan/extrinsic
/// - Gets detailed status including success/failure from indexed data
struct PolkadotTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(txHash: String, chain: Chain) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                PolkadotTransactionStatusAPI.getExtrinsic(extrinsicHash: txHash),
                responseType: PolkadotTransactionStatusResponse.self
            )

            // Check API response code
            if response.data.code != 0 {
                // Non-zero code means transaction not found in Subscan
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Check if extrinsic data exists
            guard let extrinsicData = response.data.data else {
                // code: 0 with data: null means transaction not indexed yet (pending)
                return TransactionStatusResult(
                    status: .pending,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            let blockNumber = extrinsicData.block_num

            // Check if extrinsic is finalized
            if let finalized = extrinsicData.finalized, !finalized {
                return TransactionStatusResult(
                    status: .pending,
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            }

            // Check if extrinsic succeeded or failed
            if extrinsicData.success {
                return TransactionStatusResult(
                    status: .confirmed,
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            } else {
                let failureReason = buildFailureReason(error: extrinsicData.error)
                return TransactionStatusResult(
                    status: .failed(reason: failureReason),
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            }

        } catch let error as HTTPError {
            if case .statusCode(let code, _) = error, code == 404 {
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }
            throw error
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
