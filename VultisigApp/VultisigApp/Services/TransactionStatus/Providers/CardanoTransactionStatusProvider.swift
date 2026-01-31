//
//  CardanoTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Cardano Transaction Status Logic:
/// - Uses Koios API POST /tx_status endpoint
/// - Returns array with tx_hash and num_confirmations
/// - Empty array means transaction not found
/// - num_confirmations == nil means pending (in mempool)
/// - num_confirmations >= 1 means confirmed
struct CardanoTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                CardanoTransactionStatusAPI.getTxStatus(txHash: query.txHash),
                responseType: CardanoTransactionStatusResponse.self
            )

            // Check if transaction exists in response
            guard let txStatus = response.data.txStatuses.first else {
                // Empty array means transaction not found
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Check num_confirmations
            if let confirmations = txStatus.num_confirmations {
                if confirmations >= 1 {
                    // Transaction confirmed in a block
                    return TransactionStatusResult(
                        status: .confirmed,
                        blockNumber: nil,  // Koios doesn't return block number in tx_status
                        confirmations: confirmations
                    )
                } else {
                    // 0 confirmations - still pending
                    return TransactionStatusResult(
                        status: .pending,
                        blockNumber: nil,
                        confirmations: 0
                    )
                }
            } else {
                // num_confirmations is nil - transaction in mempool (pending)
                return TransactionStatusResult(
                    status: .pending,
                    blockNumber: nil,
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
}
