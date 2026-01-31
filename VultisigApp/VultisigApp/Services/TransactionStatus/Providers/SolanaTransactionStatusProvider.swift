//
//  SolanaTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

struct SolanaTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        let response = try await httpClient.request(
            SolanaTransactionStatusAPI.getSignatureStatuses(txHash: query.txHash),
            responseType: SolanaTransactionStatusResponse.self
        )

        guard let result = response.data.result,
              let statusValue = result.value.first as? SolanaTransactionStatusResponse.SolanaStatusValue else {
            // Transaction not found
            return TransactionStatusResult(
                status: .notFound,
                blockNumber: nil,
                confirmations: nil
            )
        }

        // Check confirmationStatus
        if let confirmationStatus = statusValue.confirmationStatus {
            switch confirmationStatus {
            case "finalized":
                // Check for errors
                if let _ = statusValue.err {
                    return TransactionStatusResult(
                        status: .failed(reason: "Transaction error"),
                        blockNumber: nil,
                        confirmations: nil
                    )
                }

                return TransactionStatusResult(
                    status: .confirmed,
                    blockNumber: statusValue.slot,
                    confirmations: nil
                )

            case "confirmed", "processed":
                // Still pending finalization
                return TransactionStatusResult(
                    status: .pending,
                    blockNumber: nil,
                    confirmations: nil
                )

            default:
                return TransactionStatusResult(
                    status: .pending,
                    blockNumber: nil,
                    confirmations: nil
                )
            }
        }

        // No status = not found
        return TransactionStatusResult(
            status: .notFound,
            blockNumber: nil,
            confirmations: nil
        )
    }
}
