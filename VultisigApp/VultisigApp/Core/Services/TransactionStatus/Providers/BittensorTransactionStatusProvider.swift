//
//  BittensorTransactionStatusProvider.swift
//  VultisigApp
//

import Foundation

/// Bittensor Transaction Status Logic:
/// - Calls the Vultisig tao-tx proxy (Taostats under the hood)
/// - Returns `data: [{ success, block_number }, ...]`
/// - Empty data array → tx not yet observed (pending)
/// - `success` bool present → confirmed (true) or failed (false)
/// - `success` missing → still pending
struct BittensorTransactionStatusProvider: TransactionStatusProvider {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        let txHash = query.txHash.hasPrefix("0x") ? query.txHash : "0x\(query.txHash)"

        do {
            let response = try await httpClient.request(
                BittensorTransactionStatusAPI.getExtrinsic(txHash: txHash),
                responseType: BittensorTransactionStatusResponse.self
            )

            guard let first = response.data.data.first else {
                return TransactionStatusResult(status: .pending, blockNumber: nil, confirmations: nil)
            }

            if let success = first.success {
                return TransactionStatusResult(
                    status: success ? .confirmed : .failed(reason: "Transaction failed on Bittensor network"),
                    blockNumber: first.blockNumber,
                    confirmations: nil
                )
            }

            return TransactionStatusResult(status: .pending, blockNumber: first.blockNumber, confirmations: nil)
        } catch let error as HTTPError {
            if case .statusCode(let code, _) = error, code == 404 {
                return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
            }
            throw error
        }
    }
}
