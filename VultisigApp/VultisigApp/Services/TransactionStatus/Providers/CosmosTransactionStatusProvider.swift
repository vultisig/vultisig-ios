//
//  CosmosTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 23/01/2025.
//

import Foundation

struct CosmosTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                CosmosTransactionStatusAPI.getTransactionStatus(txHash: query.txHash, chain: query.chain),
                responseType: CosmosTransactionStatusResponse.self
            )

            // Parse to check for success/failure
            if let txResponse = response.data.txResponse {
                // code 0 = success, non-zero = failure
                if txResponse.code == 0 {
                    let blockNum = txResponse.height.flatMap { Int($0) }

                    return TransactionStatusResult(
                        status: .confirmed,
                        blockNumber: blockNum,
                        confirmations: nil
                    )
                } else {
                    let rawLog = txResponse.rawLog ?? "Transaction failed"
                    return TransactionStatusResult(
                        status: .failed(reason: rawLog),
                        blockNumber: nil,
                        confirmations: nil
                    )
                }
            }

            // No tx_response but 200 = assume success
            return TransactionStatusResult(
                status: .confirmed,
                blockNumber: nil,
                confirmations: nil
            )
        } catch let error as HTTPError {
            // 404 = transaction not found (still pending)
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
