//
//  TonTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// TON Transaction Status Logic:
/// - Uses TON Center API v3 `/v3/transactionsByMessage` endpoint, querying by
///   incoming message hash.
/// - Empty `transactions` array → not found, keep polling.
/// - A returned transaction without a `description` block hasn't finished
///   indexing → keep polling. (Matches Android, avoids prematurely marking
///   the tx as confirmed before TON Center has populated execution details.)
/// - `description.aborted == true` → failed.
/// - `description.compute_ph.exit_code`: nil (non-contract transfer) or 0/1
///   (TVM success conventions) → confirmed; any other code → failed with the
///   exit code in the reason string. (Matches the SDK / Windows resolver at
///   `vultisig-sdk/packages/core/chain/tx/status/resolvers/ton.ts`.)
///
/// `lt` (logical time) is intentionally not exposed as `blockNumber` — it is
/// not a block height and TON has no single block number for a transaction.
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

            return resolve(transactions: response.data.transactions)

        } catch let error as HTTPError {
            if case .statusCode(let code, _) = error, code == 404 {
                return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
            }
            throw error
        }
    }

    private func resolve(transactions: [TonTransactionStatusResponse.TonTransaction]?) -> TransactionStatusResult {
        guard let transaction = transactions?.first else {
            return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
        }

        guard let description = transaction.description else {
            // Transaction is indexed but execution details haven't landed
            // yet. Poll again rather than declaring success.
            return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
        }

        if description.aborted == true {
            return TransactionStatusResult(status: .failed(reason: "Transaction aborted"), blockNumber: nil, confirmations: nil)
        }

        if let exitCode = description.computePhase?.exitCode, exitCode != 0, exitCode != 1 {
            return TransactionStatusResult(
                status: .failed(reason: "Compute phase exited with code \(exitCode)"),
                blockNumber: nil,
                confirmations: nil
            )
        }

        return TransactionStatusResult(status: .confirmed, blockNumber: nil, confirmations: nil)
    }
}
