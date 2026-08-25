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

        guard let firstValue = response.data.result?.value.first,
              let statusValue = firstValue else {
            // Transaction not found
            return TransactionStatusResult(
                status: .notFound,
                blockNumber: nil,
                confirmations: nil
            )
        }

        if statusValue.err != nil {
            return TransactionStatusResult(
                status: .failed(reason: "transactionFailed".localized),
                blockNumber: nil,
                confirmations: nil
            )
        }

        switch statusValue.confirmationStatus {
        case "confirmed", "finalized":
            return TransactionStatusResult(
                status: .confirmed,
                blockNumber: statusValue.slot,
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
}
