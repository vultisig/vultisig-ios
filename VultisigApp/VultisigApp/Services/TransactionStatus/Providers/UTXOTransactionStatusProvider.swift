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

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                UTXOTransactionStatusAPI.getTransactionStatus(txHash: query.txHash, chain: query.chain),
                responseType: UTXOTransactionStatusResponse.self
            )

            // Handle Blockchair format
            if let txDict = response.data.data, let txData = txDict[query.txHash] {
                let transaction = txData.transaction

                if transaction.isConfirmed {
                    return TransactionStatusResult(
                        status: .confirmed,
                        blockNumber: transaction.blockNumber,
                        confirmations: nil
                    )
                } else {
                    return TransactionStatusResult(
                        status: .pending,
                        blockNumber: nil,
                        confirmations: nil
                    )
                }
            }

            // No data or transaction not in dictionary = transaction not found
            return TransactionStatusResult(
                status: .notFound,
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
