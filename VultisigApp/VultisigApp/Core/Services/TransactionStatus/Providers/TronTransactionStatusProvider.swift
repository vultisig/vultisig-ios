//
//  TronTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Tron Transaction Status Logic:
/// - If receipt.result is nil or "SUCCESS" → SUCCESS
/// - Any other receipt.result → FAILED (contains error like "OUT_OF_ENERGY", "REVERT", etc.)
/// - Top-level result field may also indicate "FAILED" with resMessage
/// - Anything it cannot resolve, and that carries no block number, is checked
///   against the transaction's own `expiration`
struct TronTransactionStatusProvider: TransactionStatusProvider {

    /// Stored raw and localized when rendered, via
    /// `TransactionHistoryFailureReasonPresentation`.
    static let expiredReason = "EXPIRED: transaction expired before it was included in a block"

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                TronTransactionStatusAPI.getTransactionInfo(txHash: query.txHash),
                responseType: TronTransactionStatusResponse.self
            )

            // Check if transaction exists
            guard let txId = response.data.id, !txId.isEmpty else {
                return await unconfirmedStatus(txHash: query.txHash, isKnown: false, blockNumber: nil)
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
                if let receiptResult = receipt.result,
                   receiptResult.caseInsensitiveCompare("SUCCESS") != .orderedSame {
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

                return TransactionStatusResult(
                    status: .confirmed,
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            }

            // Must stay ahead of the expiry probe. A block number means the
            // transaction was included, and `gettransactionbyid` answers for
            // included transactions too — so the probe cannot tell a landed
            // transfer from an unconfirmed one and would report it failed,
            // inviting a duplicate payment.
            if let blockNumber, blockNumber > 0 {
                return TransactionStatusResult(
                    status: .pending,
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            }

            return await unconfirmedStatus(txHash: query.txHash, isKnown: true, blockNumber: blockNumber)

        } catch let error as HTTPError {
            if case .statusCode(let code, _) = error, code == 404 {
                return await unconfirmedStatus(txHash: query.txHash, isKnown: false, blockNumber: nil)
            }
            throw error
        }
    }

    /// The expiration lives only on the raw transaction, so read that before
    /// answering. Bounded by what the node still holds: once it has dropped the
    /// transaction there is no expiration to read and the answer is the old one.
    private func unconfirmedStatus(
        txHash: String,
        isKnown: Bool,
        blockNumber: Int?
    ) async -> TransactionStatusResult {
        let rawTransaction = try? await httpClient.request(
            TronTransactionStatusAPI.getTransactionById(txHash: txHash),
            responseType: TronRawTransactionResponse.self
        ).data

        guard let rawTransaction,
              let rawTxId = rawTransaction.txID,
              rawTxId.caseInsensitiveCompare(txHash) == .orderedSame else {
            return TransactionStatusResult(
                status: isKnown ? .pending : .notFound,
                blockNumber: blockNumber,
                confirmations: nil
            )
        }

        // The node still holds it, so it is known even if the info endpoint
        // said nothing.
        let pending = TransactionStatusResult(
            status: .pending,
            blockNumber: blockNumber,
            confirmations: nil
        )
        guard let expiration = rawTransaction.raw_data?.expiration else {
            return pending
        }

        // Chain time only. TRON validates `expiration` against block time, so
        // the device clock is not evidence either way: a fast one would call a
        // live transaction failed, a slow one would never let it go terminal at
        // all. An unreachable node leaves it pending.
        guard let chainTimeMillis = await chainTimeMillis(),
              chainTimeMillis > expiration else {
            return pending
        }

        return TransactionStatusResult(
            status: .expired(reason: Self.expiredReason),
            blockNumber: blockNumber,
            confirmations: nil
        )
    }

    private func chainTimeMillis() async -> Int64? {
        let block = try? await httpClient.request(
            TronTransactionStatusAPI.getNowBlock,
            responseType: TronNowBlockResponse.self
        ).data
        guard let timestamp = block?.block_header?.raw_data?.timestamp else { return nil }
        return Int64(exactly: timestamp)
    }

    private func buildFailureReason(receiptResult: String, resMessage: String?) -> String {
        if let message = resMessage, !message.isEmpty {
            return "\(receiptResult): \(message)"
        }
        return receiptResult
    }
}
