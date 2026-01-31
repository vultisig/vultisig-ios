//
//  SuiTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

struct SuiTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                SuiTransactionStatusAPI.getTransactionBlock(txHash: query.txHash),
                responseType: SuiTransactionStatusResponse.self
            )

            // Check for RPC error
            if let error = response.data.error {
                // Error code -32602 typically means transaction not found
                if error.code == -32602 {
                    return TransactionStatusResult(
                        status: .notFound,
                        blockNumber: nil,
                        confirmations: nil
                    )
                }
                // Other error
                return TransactionStatusResult(
                    status: .failed(reason: error.message),
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Parse successful response
            if let result = response.data.result, let effects = result.effects {
                let blockNum = result.checkpoint.flatMap { Int($0) }

                if effects.status.status.lowercased() == "success" {
                    return TransactionStatusResult(
                        status: .confirmed,
                        blockNumber: blockNum,
                        confirmations: nil
                    )
                } else {
                    return TransactionStatusResult(
                        status: .failed(reason: "Transaction failed"),
                        blockNumber: blockNum,
                        confirmations: nil
                    )
                }
            }

            // No result
            return TransactionStatusResult(
                status: .notFound,
                blockNumber: nil,
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
