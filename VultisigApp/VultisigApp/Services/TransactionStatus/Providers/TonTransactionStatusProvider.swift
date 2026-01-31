//
//  TonTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// TON Transaction Status Logic:
/// - Uses TON Center API v3 transactionsByMessage endpoint
/// - Searches for transaction by incoming message hash
/// - Checks description.aborted field to determine success/failure
/// - Empty transactions array means transaction not found
struct TonTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                TonTransactionStatusAPI.getTransactionsByMessage(msgHash: query.txHash),
                responseType: TonTransactionStatusResponse.self
            )

            // Check if transaction exists
            guard let transactions = response.data.transactions, !transactions.isEmpty else {
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Get first transaction (should only be one for a specific message hash)
            let transaction = transactions[0]

            // Extract logical time as block reference
            let blockNumber: Int?
            if let lt = transaction.lt, let ltInt = Int(lt) {
                blockNumber = ltInt
            } else {
                blockNumber = nil
            }

            // Check if transaction was aborted
            if let aborted = transaction.description?.aborted, aborted == true {
                return TransactionStatusResult(
                    status: .failed(reason: "Transaction aborted"),
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            }

            // Transaction exists and was not aborted - confirmed
            return TransactionStatusResult(
                status: .confirmed,
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
}
