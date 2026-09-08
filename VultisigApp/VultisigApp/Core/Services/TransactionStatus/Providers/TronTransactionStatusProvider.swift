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
/// - Anything the info endpoint cannot resolve, and that carries no block
///   number, is checked against the transaction's own `expiration` before
///   being reported as still in flight
struct TronTransactionStatusProvider: TransactionStatusProvider {

    /// Recorded on the expired row. Joins the raw chain-code reasons this
    /// provider already surfaces (`OUT_OF_ENERGY: …`) rather than introducing
    /// the only localized one among them.
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

            // A block number is evidence the transaction was included; it is
            // waiting for its receipt, not running out of time. The expiry
            // probe must not run here: `gettransactionbyid` answers for
            // included transactions too, so it cannot tell an unconfirmed
            // transaction from a landed one, and reporting a landed transfer
            // as terminally failed would invite the user to send it twice.
            if let blockNumber, blockNumber > 0 {
                return TransactionStatusResult(
                    status: .pending,
                    blockNumber: blockNumber,
                    confirmations: nil
                )
            }

            // No block: either still waiting for one, or already past the
            // expiration its payload carries.
            return await unconfirmedStatus(txHash: query.txHash, isKnown: true, blockNumber: blockNumber)

        } catch let error as HTTPError {
            if case .statusCode(let code, _) = error, code == 404 {
                return await unconfirmedStatus(txHash: query.txHash, isKnown: false, blockNumber: nil)
            }
            throw error
        }
    }

    /// Resolves a transaction the info endpoint could not settle. A TRON
    /// transaction carries an `expiration`; once it passes unconfirmed the
    /// transaction can never be included, and polling it as `notFound` forever
    /// leaves the row in flight for good. The expiration lives only on the raw
    /// transaction, so read that before answering.
    ///
    /// Bounded by what the node still holds: once it has dropped the
    /// transaction there is no expiration to read and the answer is the old
    /// one. That is the same bound the SDK's resolver has.
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

        // The node still holds the transaction, so it is known even when the
        // info endpoint had nothing to say about it.
        let pending = TransactionStatusResult(
            status: .pending,
            blockNumber: blockNumber,
            confirmations: nil
        )
        guard let expiration = rawTransaction.raw_data?.expiration else {
            return pending
        }

        // The device clock is only the cheap gate. TRON validates `expiration`
        // against block time, so a phone running fast would otherwise report a
        // perfectly live transaction as permanently failed. Confirm against the
        // chain before making a terminal claim, and stay pending if that
        // lookup fails — an unreachable node is not evidence of anything.
        guard Int64(Date().timeIntervalSince1970 * 1000) > expiration,
              let chainTimeMillis = await chainTimeMillis(),
              chainTimeMillis > expiration else {
            return pending
        }

        return TransactionStatusResult(
            status: .expired(reason: Self.expiredReason),
            blockNumber: blockNumber,
            confirmations: nil
        )
    }

    /// Head-block timestamp in milliseconds, or nil when it cannot be read.
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
