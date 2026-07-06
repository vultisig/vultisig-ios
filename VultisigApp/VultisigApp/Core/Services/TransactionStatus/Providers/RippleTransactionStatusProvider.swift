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
    private let retrier: RippleRequestRetrier
    /// Resolves the Ripple custom RPC override so the status lookup targets the
    /// same host as broadcast/reads (`RippleService`).
    private let resolver: RPCEndpointResolving

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        sleep: @escaping RippleRequestRetrier.Sleeper = RippleRequestRetrier.defaultSleep,
        resolver: RPCEndpointResolving = CustomRPCStore.shared
    ) {
        self.retrier = RippleRequestRetrier(httpClient: httpClient, sleep: sleep)
        self.resolver = resolver
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let host = resolver.resolvedURL(for: .ripple, default: RippleAPI.defaultHost)
            let response = try await retrier.request(
                RippleTransactionStatusAPI.getTx(txHash: query.txHash, host: host),
                responseType: RippleTransactionStatusResponse.self
            )

            // Check for error response
            if let error = response.error {
                if error == "txnNotFound" {
                    return TransactionStatusResult(
                        status: .notFound,
                        blockNumber: nil,
                        confirmations: nil
                    )
                }
                // Other errors
                let message = response.error_message ?? error
                return TransactionStatusResult(
                    status: .failed(reason: message),
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Parse successful result
            guard let result = response.result else {
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
