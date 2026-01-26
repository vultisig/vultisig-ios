//
//  UTXOTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

struct UTXOTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(txHash: String, chain: Chain) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                UTXOTransactionStatusAPI.getTransactionStatus(txHash: txHash, chain: chain),
                responseType: UTXOTransactionStatusResponse.self
            )

            // Check for status field
            if let status = response.data.status {
                if status.confirmed {
                    // Transaction confirmed
                    return TransactionStatusResult(
                        status: .confirmed,
                        blockNumber: status.blockHeight,
                        confirmations: nil
                    )
                } else {
                    // In mempool but not confirmed
                    return TransactionStatusResult(
                        status: .pending,
                        blockNumber: nil,
                        confirmations: nil
                    )
                }
            }

            // No status field = pending
            return TransactionStatusResult(
                status: .pending,
                blockNumber: nil,
                confirmations: nil
            )
        } catch let error as HTTPError {
            // 404 = transaction not found (still pending or not broadcast)
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
