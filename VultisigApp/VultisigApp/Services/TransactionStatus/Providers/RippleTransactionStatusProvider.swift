//
//  RippleTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// XRP Ledger Transaction Status Provider
/// - Uses the `tx` JSON-RPC method to retrieve transaction information
/// - Checks `validated` field to confirm transaction finality
/// - Parses `TransactionResult` to determine success/failure
struct RippleTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(txHash: String, chain: Chain) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                RippleTransactionStatusAPI.getTx(txHash: txHash),
                responseType: RippleTransactionStatusResponse.self
            )

            // Check for error response
            if let error = response.data.error {
                if error == "txnNotFound" {
                    return TransactionStatusResult(
                        status: .notFound,
                        blockNumber: nil,
                        confirmations: nil
                    )
                }
                // Other errors
                let message = response.data.error_message ?? error
                return TransactionStatusResult(
                    status: .failed(reason: message),
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Parse successful result
            guard let result = response.data.result else {
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Check if result contains an error
            if result.status == "error" {
                if result.error == "txnNotFound" {
                    return TransactionStatusResult(
                        status: .notFound,
                        blockNumber: nil,
                        confirmations: nil
                    )
                }
                // Other errors (e.g., "notImpl", invalid params)
                // Use transaction field from request if available (contains error description)
                let message = result.request?.transaction
                    ?? result.error_message
                    ?? result.error
                    ?? "Unknown error"
                return TransactionStatusResult(
                    status: .failed(reason: message),
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Check if transaction is validated
            if result.validated == true {
                // Transaction is finalized in a validated ledger
                if let meta = result.meta {
                    let txResult = meta.TransactionResult

                    if txResult == "tesSUCCESS" {
                        // Transaction succeeded
                        return TransactionStatusResult(
                            status: .confirmed,
                            blockNumber: result.ledger_index,
                            confirmations: nil
                        )
                    } else {
                        // Transaction failed with error code
                        return TransactionStatusResult(
                            status: .failed(reason: txResult),
                            blockNumber: result.ledger_index,
                            confirmations: nil
                        )
                    }
                }

                // Validated but no meta (older transactions) - assume success
                return TransactionStatusResult(
                    status: .confirmed,
                    blockNumber: result.ledger_index,
                    confirmations: nil
                )
            }

            // Not validated yet - still pending
            return TransactionStatusResult(
                status: .pending,
                blockNumber: result.ledger_index,
                confirmations: nil
            )

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
}
