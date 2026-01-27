//
//  TronTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Tron Transaction Status Logic:
/// - receipt.result is ONLY present when transaction fails
/// - If receipt exists but receipt.result is nil → SUCCESS
/// - If receipt.result exists → FAILED (contains error like "OUT_OF_ENERGY", "REVERT", etc.)
/// - Top-level result field may also indicate "FAILED" with resMessage
struct TronTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(txHash: String, chain: Chain) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                TronTransactionStatusAPI.getTransactionInfo(txHash: txHash),
                responseType: TronTransactionStatusResponse.self
            )

            // Check if transaction exists
            guard let txId = response.data.id, !txId.isEmpty else {
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            let blockNumber = response.data.blockNumber

            // Check top-level result field first (present on some failures)
            if let topLevelResult = response.data.result, topLevelResult == "FAILED" {
                let failureReason = response.data.resMessage ?? "Transaction failed"
                return TransactionStatusResult(
                    status: .failed(reason: failureReason),
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            }

            // Check receipt
            if let receipt = response.data.receipt {
                // If receipt.result is present, transaction failed
                if let receiptResult = receipt.result {
                    let failureReason = buildFailureReason(
                        receiptResult: receiptResult,
                        resMessage: response.data.resMessage
                    )
                    return TransactionStatusResult(
                        status: .failed(reason: failureReason),
                        blockNumber: blockNumber,
                        confirmations: nil
                    )
                }

                // receipt exists but receipt.result is nil → SUCCESS
                return TransactionStatusResult(
                    status: .confirmed,
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            }

            // Transaction exists but no receipt yet (still pending)
            return TransactionStatusResult(
                status: .pending,
                blockNumber: blockNumber,
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

    private func buildFailureReason(receiptResult: String, resMessage: String?) -> String {
        if let message = resMessage, !message.isEmpty {
            return "\(receiptResult): \(message)"
        }
        return receiptResult
    }
}
